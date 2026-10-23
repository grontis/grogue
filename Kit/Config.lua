-- gkit Config.lua @ 3b70925: edit gkit, not this copy
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
--   validators   0.3.0. { key = function(value) return clean, droppedCount end }: settings the addon
--                checks whole, such as a list of tabs or a map of colors (gChat's). The function
--                gets a value of the default's type that has passed the checks above, and returns
--                the value cleaned (a table of its own; it leaves the one handed in as it was), or
--                nil to refuse it, and how many of its parts it had to drop (0 or nil: none). A
--                cleaned value of another type than the default's counts as a refusal, and so does
--                a validator that throws (its error recorded, keyed "Config <key>")
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
--   Valid(key, value) -> ok, why        the default's type, within limits, on the list, a colour;
--                                       and where the setting has a validator, one that does not
--                                       refuse it (a value it had to trim is still valid)
--   ValidEntry(key, k, v) -> ok         an entry of a table setting: the default entry's shape, a
--                                       colour where the default entry is one
--   Prune(stored) -> kept, dropped      0.3.0. what ADDON_LOADED does to <db>.settings, for a layer
--                                       that prunes each stored profile itself: the values this
--                                       version can use, in a new table (stored's own values, or
--                                       what a validator returned; not copies), and the names of
--                                       the rest, sorted. Pure: stored, the save and dropped are
--                                       left as they are
--   IsColourKey(key)
--   dropped, reloadChanges              saved values refused at load (names, sorted); a count of
--                                       changes to reload keys
-- and ns.dbLoaded, whether the client handed back a save this session.
--
-- Rules kept from the lineage (gBars' saved-false fix and validation, gFrames' resolve): a saved false
-- loads as false (no `a and b or c` anywhere); each saved value is checked on its own and an
-- unusable one is dropped and named; only values that differ from their defaults are saved, so a
-- later change to a default reaches everyone who never touched that setting. A table setting (a
-- list of colours, a frame's place) is merged over a copy of its default entry by entry, and an
-- entry without the default entry's shape keeps the default one; a colour is checked whole, so a
-- partial one is replaced whole.
--
-- A setting with a validator (0.3.0) is never merged: a merge keeps only the default's entries, so
-- a list of four tabs would load as the default's two, and a map whose default is empty would load
-- empty, as gChat's tabs once did. Its saved value loads as the validator cleaned it, or as the
-- default when the validator refuses it. Set takes only a value the validator keeps whole (one it
-- had to trim is refused, as gChat's own Set refuses it), and stores and compares what the validator
-- returned. The prune keeps the cleaned value, names a refused one as any other ("key"), and names
-- a trimmed one "key (n dropped)". ValidEntry, the merge's check, does not look at validators: a
-- layer prunes with Prune, which does. Settings without a validator behave exactly as before.
--
-- Profiles are not here; a profile layer sits on top (gFrames' Config/Config.lua). It points
-- ns.kit.config.saved at the profile in use (a table of values that differ), so Set and Reset
-- write there; at ADDON_LOADED this file then records ns.dbLoaded and touches nothing else, since
-- the layer carries over and prunes each stored profile itself (with Prune, or Valid/ValidEntry,
-- as this file prunes <db>.settings); the layer loads the profile in use with Config.Load and
-- switches with Config.Apply, which notifies every listener of a setting that changed.
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
local tsort, huge, ceil = table.sort, math.huge, math.ceil

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
local spec, defaults, limits, choices, colourKeys, reloadKeys, form, validators

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
    validators = spec.validators or {}
    if type(validators) ~= "table" then
        error("gkit Config: ns.kit.config.validators is a table of functions", 3)
    end
    for key, fn in pairs(validators) do
        if type(fn) ~= "function" then
            error("gkit Config: ns.kit.config.validators." .. tostring(key) .. " is not a function", 3)
        end
    end
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

local function notValid(key)
    return false, ("%s is not valid"):format(tostring(key))
end

-- How many parts a validator said it dropped, as a whole number: 0 for none, nil or anything but
-- a positive number.
local function dropCount(n)
    if type(n) ~= "number" or not (n > 0) then
        return 0
    end
    if n >= 2147483647 then
        return 2147483647
    end
    return ceil(n)
end

-- The last of the checks: true, nil, the value and 0 for a setting without a validator; for one
-- with, what its validator made of the value (guarded: a validator that throws refuses it).
local function validated(key, value)
    local validator = validators[key]
    if validator == nil then
        return true, nil, value, 0
    end
    local ran, clean, dropped = Init.Run("Config " .. tostring(key), validator, value)
    if not ran or clean == nil or type(clean) ~= type(defaults[key]) then
        return notValid(key)
    end
    return true, nil, clean, dropCount(dropped)
end

-- ok, why, then for a usable value the value to keep (a validator's cleaned one) and how many parts
-- the validator dropped. Without a validator, what Valid always answered.
local function check(key, value)
    local default = defaults[key]
    if default == nil then
        return false, "no such setting: " .. tostring(key)
    end
    if type(value) ~= type(default) then
        return false, ("%s expects a %s"):format(tostring(key), type(default))
    end
    if Config.IsColourKey(key) then
        if isColourValue(value) then
            return validated(key, value)
        end
        return cannot(key, value)
    end
    if type(value) == "number" then
        local range = limits[key]
        if range then
            if value >= range[1] and value <= range[2] then
                return validated(key, value)
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
        return validated(key, value)
    end
    for _, choice in ipairs(list) do
        if choice == value then
            return validated(key, value)
        end
    end
    return cannot(key, value)
end

function Config.Valid(key, value)
    if not built then build() end
    local ok, why = check(key, value)
    if ok then
        return true
    end
    return false, why
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

-- A table setting that is not one colour and has no validator: merged entry by entry.
local function mergedKey(key)
    return type(defaults[key]) == "table" and validators[key] == nil and not Config.IsColourKey(key)
end

local function resolve(key, stored)
    local default = defaults[key]
    local ok, _, clean = check(key, stored)
    if not ok then
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
    return copy(clean)
end

-- Not `Valid(key, value) and copy(value) or copy(default)`: that loads the default when the value
-- is false, so every unticked check box came back ticked (in gBars).
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
-- is every unticked check box. A setting with a validator takes only a value the validator kept
-- whole, and what is stored and compared is the value it returned.
function Config.Set(key, value)
    if not built then build() end
    local ok, why, clean, dropped = check(key, value)
    if not ok then
        return false, why
    end
    if dropped > 0 then
        return notValid(key)
    end
    value = clean
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
-- that is not a string, a value of the wrong type, past its limits, off its list, not a colour or
-- refused by its validator, and in a table setting an entry the merge would skip ("key.entry").
-- A setting with a validator keeps the value it cleaned, named "key (n dropped)" when that took
-- parts out.
local function prune(stored)
    local kept, dropped = {}, {}
    for key, value in pairs(stored) do
        local ok, clean, n = false, nil, 0
        if type(key) == "string" then
            local _
            ok, _, clean, n = check(key, value)
        end
        if not ok then
            dropped[#dropped + 1] = tostring(key)
        elseif validators[key] ~= nil then
            kept[key] = clean
            if n > 0 then
                dropped[#dropped + 1] = ("%s (%d dropped)"):format(key, n)
            end
        elseif mergedKey(key) then
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
    end
    tsort(dropped)
    return kept, dropped
end

-- 0.3.0. The prune above for a profile layer, which prunes each stored profile itself (gFrames'
-- and gChat's): nothing here is changed by it, the stored set included.
function Config.Prune(stored)
    if not built then build() end
    if type(stored) ~= "table" then
        return {}, {}
    end
    return prune(stored)
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
