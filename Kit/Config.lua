-- gkit Config.lua @ f0ef885: edit gkit, not this copy
-- Config.lua -- settings: defaults, what was saved, validated, into one live set.
--
--   ns.kit.config.defaults  ->  <ns.kit.db>.settings (SavedVariables), the values that differ only
--
-- Needs Kit/Init.lua. Reads ns.kit.db (the SavedVariables global's name) and ns.kit.config:
--   defaults     every setting and its shipped value (required)
--   limits       { key = { min, max } } for numbers; a number without limits must be finite
--   choices      { key = { value, ... } } for settings limited to a list
--   colours      "hex" (six hex digits, "C2463F") or "rgb" ({ r =, g =, b = }, each 0..1): how a
--                colour setting is kept; "rgb" when not given
--   colourKeys   { key = true }: the colour settings. When not given, a setting is a colour when
--                its default is one in that form
--   reloadKeys   { key = true }: settings that apply after /reload (PendingReload)
--   liveKeys     { key = true }: settings the addon applies itself, at once (not used here; kept
--                with the rest for the addon's own code)
--   store        false: the addon keeps its own save and uses only Valid and ValidEntry; no
--                loading or saving happens here. Otherwise the settings live in <db>.settings
--   saved        function returning the table Set writes to, instead of <db>.settings (a profile
--                layer's hook, below). With it set, ADDON_LOADED leaves the save to the layer
-- The fields are read when the settings are first used, so an addon may fill ns.kit.config in its
-- own files (its defaults file), after the kit has loaded.
--
-- On ns.Config (and ns.Kit.Config):
--   Get(key), Set(key, value) -> true | false, why      a value equal to its default leaves the save
--   OnChange(key, fn), OnAnyChange(fn)                  fn(value); fn(key, value), and fn() once
--                                                       after Apply
--   Reset(), ResetKeys(keys), Changed(), PendingReload(), NeedsReload()
--   Apply(stored)        a whole stored set at once (a profile switch): every value first, then the
--                        listeners of each that changed, then the any-listeners once
--   Load(stored)         a whole stored set as what this session runs with (a profile chosen at
--                        login, before anything is built from the settings): every value, checked
--                        as at load, no listener told, nothing counted, and the reload keys'
--                        values become what PendingReload measures against
--   Loading()            true while Apply runs
--   Valid(key, value) -> ok, why        the default's type, within limits, on the list, a colour
--   ValidEntry(key, k, v) -> ok         an entry of a table setting: the default entry's shape, a
--                                       colour where the default entry is one
--   IsColourKey(key)
--   dropped, reloadChanges              saved values refused at load (names, sorted); a count of
--                                       changes to reload keys
-- and ns.dbLoaded, whether the client handed back a save this session.
--
-- Rules kept from the lineage (gBars' GB2-H1, gFrames' resolve, gBars' validation): a saved false
-- loads as false (no `a and b or c` anywhere); each saved value is checked on its own and an
-- unusable one is dropped and named; only values that differ from their defaults are saved, so a
-- later change to a default reaches everyone who never touched that setting. A table setting (a
-- list of colours, a frame's place) is merged over a copy of its default entry by entry, and an
-- entry without the default entry's shape keeps the default one; a colour is checked whole, so a
-- partial one is replaced whole.
--
-- Profiles are not here; a profile layer sits on top (gFrames' Config/Config.lua). It points
-- ns.kit.config.saved at the profile in use (a table of values that differ), so Set and Reset
-- write there; at ADDON_LOADED this file then records ns.dbLoaded and touches nothing else, since
-- the layer carries over and prunes each stored profile itself (with Valid/ValidEntry, as this file
-- prunes <db>.settings); the layer loads the profile in use with Config.Load and switches with
-- Config.Apply, which notifies every listener of a setting that changed.
--
-- Client facts (gkit's facts/forever-client-facts.md): saved globals are assigned after the files
-- run and before ADDON_LOADED (CF-073), so the save is read there and the global is read at call
-- time; SavedVariables load since 70009 (CF-068), and ns.dbLoaded records whether that happened.

local addonName, ns = ...

local Kit = ns.Kit
if not (Kit and Kit.Init) then
    error("gkit: Kit/Init.lua must load before Kit/Config.lua", 0)
end
local Init = Kit.Init

local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local tsort, huge = table.sort, math.huge

local Config = {}
Kit.Config = Config
ns.Config = Config

Config.reloadChanges = 0
Config.dropped = {}

local live = {}           -- key -> the value in use
local listeners = {}      -- key -> { guarded fn, ... }
local anyListeners = {}   -- { guarded fn, ... }
local atLoad = {}         -- the reload keys' values this session started with
local loading = false

local built = false
local spec, defaults, limits, choices, colourKeys, reloadKeys, form

local HEX = "^%x%x%x%x%x%x$"

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy(v)
    end
    return out
end

local function equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- A value in this addon's colour form.
local function isColourValue(value)
    if form == "hex" then
        return type(value) == "string" and value:match(HEX) ~= nil
    end
    if type(value) ~= "table" then
        return false
    end
    for _, channel in ipairs({ "r", "g", "b" }) do
        local v = value[channel]
        if type(v) ~= "number" or not (v >= 0 and v <= 1) then
            return false
        end
    end
    return true
end

-- Whether a value has the default's shape: every field the default has, of the same type, all the
-- way down. A frame's place without its y does not.
local function shaped(value, default)
    if type(value) ~= type(default) then
        return false
    end
    if type(default) == "table" then
        for k, v in pairs(default) do
            if not shaped(value[k], v) then
                return false
            end
        end
    end
    return true
end

local load

local function build()
    if built then
        return
    end
    spec = ns.kit.config
    if type(spec) ~= "table" or type(spec.defaults) ~= "table" then
        error("gkit Config: ns.kit.config.defaults is not set yet", 3)
    end
    defaults = spec.defaults
    limits = spec.limits or {}
    choices = spec.choices or {}
    colourKeys = spec.colourKeys
    reloadKeys = spec.reloadKeys or {}
    form = spec.colours or "rgb"
    built = true
    load({})
end

function Config.IsColourKey(key)
    if not built then build() end
    if colourKeys then
        return colourKeys[key] == true
    end
    return defaults[key] ~= nil and isColourValue(defaults[key])
end

local function cannot(key, value)
    return false, ("%s cannot be %s"):format(tostring(key), tostring(value))
end

function Config.Valid(key, value)
    if not built then build() end
    local default = defaults[key]
    if default == nil then
        return false, "no such setting: " .. tostring(key)
    end
    if type(value) ~= type(default) then
        return false, ("%s expects a %s"):format(tostring(key), type(default))
    end
    if Config.IsColourKey(key) then
        if isColourValue(value) then
            return true
        end
        return cannot(key, value)
    end
    if type(value) == "number" then
        local range = limits[key]
        if range then
            if value >= range[1] and value <= range[2] then
                return true
            end
            return cannot(key, value)
        end
        -- NaN fails both comparisons.
        if not (value > -huge and value < huge) then
            return cannot(key, value)
        end
    end
    local list = choices[key]
    if not list then
        return true
    end
    for _, choice in ipairs(list) do
        if choice == value then
            return true
        end
    end
    return cannot(key, value)
end

function Config.ValidEntry(key, entryKey, value)
    if not built then build() end
    local default = defaults[key]
    if type(default) ~= "table" or entryKey == nil then
        return false
    end
    local entry = default[entryKey]
    if entry == nil then
        return false
    end
    if isColourValue(entry) then
        return isColourValue(value)
    end
    return shaped(value, entry)
end

-- A table setting that is not one colour: merged entry by entry.
local function mergedKey(key)
    return type(defaults[key]) == "table" and not Config.IsColourKey(key)
end

local function resolve(key, stored)
    local default = defaults[key]
    if not Config.Valid(key, stored) then
        return copy(default)
    end
    if mergedKey(key) then
        local merged = copy(default)
        for k, v in pairs(stored) do
            if Config.ValidEntry(key, k, v) then
                merged[k] = copy(v)
            end
        end
        return merged
    end
    return copy(stored)
end

-- Not `Valid(key, value) and copy(value) or copy(default)`: that loads the default when the value
-- is false, so every unticked check box came back ticked (gBars, GB2-H1).
function load(stored)
    for key in pairs(defaults) do
        live[key] = resolve(key, stored[key])
    end
    for key in pairs(reloadKeys) do
        atLoad[key] = copy(live[key])
    end
end

local function storing()
    return spec.store ~= false and type(ns.kit.db) == "string"
end

-- The table Set writes to, or nil when the addon keeps its own save.
local function savedTable()
    if not storing() then
        return nil
    end
    if spec.saved then
        return spec.saved()
    end
    local db = _G[ns.kit.db]
    if type(db) ~= "table" then
        db = {}
        _G[ns.kit.db] = db
    end
    if type(db.settings) ~= "table" then
        db.settings = {}
    end
    return db.settings
end

function Config.Get(key)
    if not built then build() end
    return live[key]
end

function Config.OnChange(key, fn)
    listeners[key] = listeners[key] or {}
    local list = listeners[key]
    list[#list + 1] = Init.Guard(fn)
end

function Config.OnAnyChange(fn)
    anyListeners[#anyListeners + 1] = Init.Guard(fn)
end

local function notify(key)
    for _, fn in ipairs(listeners[key] or {}) do
        fn(live[key])
    end
    if not loading then
        for _, fn in ipairs(anyListeners) do
            fn(key, live[key])
        end
    end
end

function Config.Loading()
    return loading
end

-- Not `differs and value or nil` for the save: that saves nothing when the value is false, which
-- is every unticked check box.
function Config.Set(key, value)
    if not built then build() end
    local ok, why = Config.Valid(key, value)
    if not ok then
        return false, why
    end
    if equal(live[key], value) then
        return true
    end
    live[key] = copy(value)
    local saved = savedTable()
    if saved then
        if equal(value, defaults[key]) then
            saved[key] = nil
        else
            saved[key] = copy(value)
        end
    end
    if reloadKeys[key] then
        Config.reloadChanges = Config.reloadChanges + 1
    end
    notify(key)
    return true
end

function Config.ResetKeys(keys)
    if not built then build() end
    for _, key in ipairs(keys) do
        local default = defaults[key]
        if default ~= nil then
            Config.Set(key, copy(default))
        end
    end
end

-- Every setting back to its shipped value, the save emptied with it.
function Config.Reset()
    if not built then build() end
    local keys = {}
    for key in pairs(defaults) do
        keys[#keys + 1] = key
    end
    tsort(keys)
    Config.ResetKeys(keys)
    if not storing() then
        return
    end
    if spec.saved then
        local saved = spec.saved()
        local stale = {}
        for key in pairs(saved) do
            stale[#stale + 1] = key
        end
        for _, key in ipairs(stale) do
            saved[key] = nil
        end
    else
        savedTable()
        _G[ns.kit.db].settings = {}
    end
end

function Config.Apply(stored)
    if not built then build() end
    local changed = {}
    for key in pairs(defaults) do
        local value = resolve(key, stored and stored[key])
        if not equal(live[key], value) then
            live[key] = value
            changed[#changed + 1] = key
            if reloadKeys[key] then
                Config.reloadChanges = Config.reloadChanges + 1
            end
        end
    end
    if #changed == 0 then
        return
    end
    tsort(changed)
    loading = true
    for _, key in ipairs(changed) do
        notify(key)
    end
    loading = false
    for _, fn in ipairs(anyListeners) do
        fn()
    end
end

-- A stored set as this session's own: what the load at ADDON_LOADED does, for a layer that picks
-- the set later (a profile, at login). Nothing is told, nothing is counted, nothing is saved.
function Config.Load(stored)
    if not built then build() end
    load(type(stored) == "table" and stored or {})
end

-- Reload keys whose value differs from the one this session started with (or Load set), sorted.
-- Setting one back takes it off the list.
function Config.PendingReload()
    if not built then build() end
    local keys = {}
    for key in pairs(reloadKeys) do
        if not equal(live[key], atLoad[key]) then
            keys[#keys + 1] = key
        end
    end
    tsort(keys)
    return keys
end

function Config.NeedsReload()
    return #Config.PendingReload() > 0
end

-- Keys whose value differs from the default, sorted.
function Config.Changed()
    if not built then build() end
    local keys = {}
    for key, default in pairs(defaults) do
        if not equal(live[key], default) then
            keys[#keys + 1] = key
        end
    end
    tsort(keys)
    return keys
end

-- The saved values this version can use, and the names of those it cannot: an unknown key, a key
-- that is not a string, a value of the wrong type, past its limits, off its list or not a colour,
-- and in a table setting an entry the merge would skip ("key.entry").
local function prune(stored)
    local kept, dropped = {}, {}
    for key, value in pairs(stored) do
        if type(key) == "string" and Config.Valid(key, value) then
            if mergedKey(key) then
                local entries = {}
                for k, v in pairs(value) do
                    if Config.ValidEntry(key, k, v) then
                        entries[k] = v
                    else
                        dropped[#dropped + 1] = key .. "." .. tostring(k)
                    end
                end
                kept[key] = entries
            else
                kept[key] = value
            end
        else
            dropped[#dropped + 1] = tostring(key)
        end
    end
    tsort(dropped)
    return kept, dropped
end

-- SavedVariables are assigned just before this addon's ADDON_LOADED (CF-073). The settings this
-- version can use stay; the rest leave the save and Config.dropped names them. Everything else at
-- the top of the save is left as it was. With a profile layer (saved), the save is the layer's:
-- only ns.dbLoaded is recorded here.
Init.On("ADDON_LOADED", function(_, name)
    if name ~= addonName then
        return
    end
    if not built then build() end
    if not storing() then
        return
    end
    local old = _G[ns.kit.db]
    ns.dbLoaded = type(old) == "table"
    if spec.saved then
        return
    end
    local stored = {}
    if ns.dbLoaded and type(old.settings) == "table" then
        stored = old.settings
    end
    local kept, dropped = prune(stored)
    Config.dropped = dropped
    local db = { settings = kept }
    if ns.dbLoaded then
        for k, v in pairs(old) do
            if k ~= "settings" then
                db[k] = v
            end
        end
    end
    _G[ns.kit.db] = db
    load(kept)
end)
