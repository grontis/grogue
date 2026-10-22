-- gkit Init.lua @ db2bf7a: edit gkit, not this copy
-- Init.lua -- gkit's core: output, error containment, the combat queue, events and diagnostics.
--
-- Vendored into <addon>/Kit/ by gkit's tools/sync.lua and listed in the TOC first among the kit's
-- files, right after the addon's own file that sets ns.kit. Every other kit module needs it.
--
-- Reads from ns.kit (all optional but name):
--   name           the addon's name as players see it, in the chat prefix
--   prefixColor    the prefix's colour, six hex digits ("4fa3d1")
--   slash          the command that lists errors ("/gbars"), named in the terse error line
--   printedErrors  how many distinct errors print in full before the terse line (10)
--   keptErrors     how many distinct errors, and own blocked actions, are kept (50)
--   disableAfter   a guarded handler's failure budget: nil never disables (gFrames, gBars); a
--                  number disables a key after that many failures until ns.Rearm (gThreat: 2)
--   pinned         { [key] = true }: keys a budget never disables
--
-- On ns:
--   Print(...), Printf(fmt, ...)    a line with the prefix; Line(...), Linef(fmt, ...) without
--   Guard([key,] fn)                fn wrapped: an error is recorded and printed, never raised;
--                                   returns whether fn ran without error. A key given is named in
--                                   the recorded message ("key: error"); one left out is generated.
--                                   Guard(fn, key), gbaggy's and gquest's order, works too.
--   guardFailures                   key -> failures this session
--   DisabledHandlers(), Rearm([key])  the keys a budget switched off; switch them (or one) on again
--   RecordError(message)            record and print an error caught elsewhere
--   errors, errorOrder, errorsDropped   message -> times seen; the first keptErrors distinct
--                                   messages; how many more distinct ones were only counted
--   TryPart(key, what, fn, ...)     an optional part: its error is recorded and noted once, and
--                                   nil comes back instead of fn's result
--   AfterCombat(key, fn)            fn now when out of combat (returns true), else once when
--                                   combat ends (returns false); a key replaces an earlier request
--   InCombat()                      true from PLAYER_REGEN_DISABLED to PLAYER_REGEN_ENABLED, or
--                                   while the lockdown is up
--   On(event, fn [, unit1, unit2]), Off(event, fn), OnLogin(fn)
--   failedEvents                    event -> why it is not delivered
--   blocked, blockedDropped         this addon's blocked and forbidden actions, the first kept
--   ledger, LedgerCount(), LedgerEntries()  every addon's: a count, the last 50, counts by addon
--   Note([key,] ok, text), NotesFor(key), notes   status notes (ok: true, false or nil)
--   Count(key [, n]), counts, Stat(key, what), stats   counters for status
--
-- Client facts relied on (gkit's facts/forever-client-facts.md): Lua errors are hidden by default
-- and only about 100 a session reach a handler (CF-140), so errors are printed and budgeted;
-- registering an unknown event throws (CF-048), so registration is under pcall; the combat log is
-- closed and registering it is forbidden (CF-076), so On refuses it; InCombatLockdown() is false
-- inside PLAYER_REGEN_DISABLED (CF-074), so "in combat" is the event seen or the lockdown up; a
-- refused protected call is silent to Lua and fires ADDON_ACTION_BLOCKED (CF-075), hence the
-- ledger; protected frames wait out combat (CF-079), hence AfterCombat.

local addonName, ns = ...

local kit = ns.kit
if type(kit) ~= "table" then
    error("gkit: set ns.kit in a file the TOC loads before Kit/Init.lua", 0)
end

local Kit = { version = "0.1.0" }
ns.Kit = Kit
ns.addonName = addonName

local pcall, select, tostring, type, ipairs, pairs = pcall, select, tostring, type, ipairs, pairs
local strformat, tconcat, tsort = string.format, table.concat, table.sort

local PRINTED = kit.printedErrors or 10
local KEPT = kit.keptErrors or 50
local LEDGER = 50

----------------------------------------------------------------------------------
-- output
--
-- Nothing is printed on load: a line in chat answers a command, or is an error or a blocked
-- action of this addon's.
----------------------------------------------------------------------------------

local PREFIX = "|cff" .. (kit.prefixColor or "ffffff") .. (kit.name or addonName) .. "|r: "

local function joined(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    return tconcat(parts, " ")
end

function ns.Print(...)
    print(PREFIX .. joined(...))
end

function ns.Printf(fmt, ...)
    print(PREFIX .. strformat(fmt, ...))
end

function ns.Line(...)
    print(joined(...))
end

function ns.Linef(fmt, ...)
    print(strformat(fmt, ...))
end

----------------------------------------------------------------------------------
-- errors
--
-- The client's error frame is off by default, so an error is printed: the first PRINTED distinct
-- ones in full, then a terse count for each new one, so a part that keeps breaking in new ways
-- does not fall silent. The first KEPT distinct messages are kept for status and the report; past
-- them new messages are only counted, so a message with a changing name in it cannot grow the
-- list, or the save, for the whole session.
----------------------------------------------------------------------------------

local errors, errorOrder = {}, {}
ns.errors, ns.errorOrder, ns.errorsDropped = errors, errorOrder, 0

local SLASH = kit.slash and (", " .. kit.slash) or ""

local function record(err)
    err = tostring(err)
    if errors[err] then
        errors[err] = errors[err] + 1
        return
    end
    if #errorOrder >= KEPT then
        ns.errorsDropped = ns.errorsDropped + 1
        return
    end
    errors[err] = 1
    errorOrder[#errorOrder + 1] = err
    if #errorOrder <= PRINTED then
        ns.Print("|cffff5555error|r " .. err)
    else
        ns.Print(strformat("|cffff5555%d errors so far|r%s", #errorOrder, SLASH))
    end
end
ns.RecordError = record

----------------------------------------------------------------------------------
-- error containment
--
-- Everything run from an event, a callback, a click or a timer goes through a guard. A key counts
-- its failures; with ns.kit.disableAfter set, a key that reaches it stops running until
-- ns.Rearm, so one broken call site in a fast loop cannot spend the session's errors (CF-140).
----------------------------------------------------------------------------------

local failures = {}
ns.guardFailures = failures

local DISABLE_AFTER = kit.disableAfter
local pinned = kit.pinned or {}
local said = {}          -- key -> true once its switching off was printed
local generated = 0

local function disabled(key)
    return DISABLE_AFTER ~= nil and not pinned[key] and (failures[key] or 0) >= DISABLE_AFTER
end

-- label: put in front of the recorded message, or nil for the message as it is.
local function guard(key, fn, label)
    return function(...)
        if disabled(key) then
            return false
        end
        local ok, err = pcall(fn, ...)
        if not ok then
            failures[key] = (failures[key] or 0) + 1
            record(label and (label .. ": " .. tostring(err)) or err)
            if disabled(key) and not said[key] then
                said[key] = true
                ns.Print(strformat("|cffff5555%s disabled for this session|r (%d errors)%s", tostring(key),
                    failures[key], kit.slash and (", " .. kit.slash .. " rearm") or ""))
            end
        end
        return ok
    end
end

local function newKey(what)
    generated = generated + 1
    return (what or "guard") .. "#" .. generated
end

function ns.Guard(key, fn)
    if fn == nil and type(key) == "function" then
        return guard(newKey(), key, nil)
    end
    if type(key) == "function" and type(fn) == "string" then
        key, fn = fn, key   -- gbaggy's and gquest's order, Guard(fn, where)
    end
    if key == nil then
        return guard(newKey(), fn, nil)
    end
    return guard(key, fn, tostring(key))
end

-- Runs fn(...) now under a guard keyed key, without naming the key in the message.
local function run(key, fn, ...)
    return guard(key, fn, nil)(...)
end

function ns.DisabledHandlers()
    local keys = {}
    for key in pairs(failures) do
        if disabled(key) then
            keys[#keys + 1] = tostring(key)
        end
    end
    tsort(keys)
    return keys
end

-- Every key, or the one given, may run again. Returns how many had been switched off.
function ns.Rearm(key)
    local keys = {}
    if key ~= nil then
        keys[1] = key
    else
        for k in pairs(failures) do
            keys[#keys + 1] = k
        end
    end
    local n = 0
    for _, k in ipairs(keys) do
        if disabled(k) then
            n = n + 1
        end
        failures[k] = nil
        said[k] = nil
    end
    return n
end

----------------------------------------------------------------------------------
-- status notes and counters
----------------------------------------------------------------------------------

local notes = {}
ns.notes = notes   -- { key = key or nil, ok = true | false | nil, text = "" }, in order
ns.counts, ns.stats = {}, {}

-- ok: true for "worked", false for "missing or failed", nil for plain information. The key may
-- be left out: Note(ok, text).
function ns.Note(key, ok, text)
    if text == nil and type(ok) == "string" and (key == nil or type(key) == "boolean") then
        key, ok, text = nil, key, ok
    end
    notes[#notes + 1] = { key = key, ok = ok, text = text }
end

function ns.NotesFor(key)
    local out = {}
    for _, note in ipairs(notes) do
        if note.key == key then
            out[#out + 1] = note
        end
    end
    return out
end

function ns.Count(key, n)
    ns.counts[key] = (ns.counts[key] or 0) + (n or 1)
end

function ns.Stat(key, what)
    local stats = ns.stats[key]
    if not stats then
        stats = {}
        ns.stats[key] = stats
    end
    stats[what] = (stats[what] or 0) + 1
end

-- An optional part (of a frame, a window, a row): one that throws is recorded, noted under key
-- once and left out, and the rest is built all the same. Returns what fn returns, or nil.
local leftOut = {}

function ns.TryPart(key, what, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    record(result)
    local id = tostring(key) .. ": " .. tostring(what)
    if not leftOut[id] then
        leftOut[id] = true
        ns.Note(key, false, tostring(what) .. " left out: " .. tostring(result))
    end
    return nil
end

----------------------------------------------------------------------------------
-- events
--
-- One frame hears every event registered without a unit, and each unit registration has a frame
-- of its own, since RegisterUnitEvent filters a frame, not a handler. Handler lists are replaced
-- rather than changed in place, so a handler added or removed while an event is being delivered
-- changes the next delivery, never the one under way.
----------------------------------------------------------------------------------

local FORBIDDEN = {
    COMBAT_LOG_EVENT = true,
    COMBAT_LOG_EVENT_UNFILTERED = true,
}

ns.failedEvents = {}

local eventFrame = CreateFrame("Frame")
local broad = {}        -- event -> { { raw = fn, fn = guarded }, ... }
local unitRoutes = {}   -- "event|unit1|unit2" -> { frame, event, unit1, unit2, list }

local function with(list, entry)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    out[#out + 1] = entry
    return out
end

local function without(list, fn)
    local out = {}
    for i = 1, #list do
        if list[i].raw ~= fn then
            out[#out + 1] = list[i]
        end
    end
    return out
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = broad[event]
    if list then
        for i = 1, #list do
            list[i].fn(event, ...)
        end
    end
end)

local function failed(event, why)
    if not ns.failedEvents[event] then
        ns.failedEvents[event] = tostring(why)
        record("could not register " .. tostring(event) .. ": " .. tostring(why))
    end
    return false
end

local handlerCount = 0

-- fn(event, ...) on each event; with units, only for those units (RegisterUnitEvent). Returns
-- whether the event is registered.
function ns.On(event, fn, unit1, unit2)
    if FORBIDDEN[event] then
        return failed(event, "refused: the client forbids the combat log to addons (gkit CF-076)")
    end
    handlerCount = handlerCount + 1
    local entry = { raw = fn, fn = guard("On " .. tostring(event) .. "#" .. handlerCount, fn, nil) }
    if unit1 == nil then
        if not broad[event] then
            local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
            if not ok then
                return failed(event, err)
            end
            broad[event] = {}
        end
        broad[event] = with(broad[event], entry)
        return true
    end
    local routeKey = strformat("%s|%s|%s", tostring(event), tostring(unit1), tostring(unit2))
    local route = unitRoutes[routeKey]
    if not route then
        local frame = CreateFrame("Frame")
        local ok, err
        if unit2 ~= nil then
            ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        else
            ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit1)
        end
        if not ok then
            return failed(event, err)
        end
        route = { frame = frame, event = event, unit1 = unit1, unit2 = unit2, list = {} }
        frame:SetScript("OnEvent", function(_, ev, unit, ...)
            if unit ~= route.unit1 and (route.unit2 == nil or unit ~= route.unit2) then
                return
            end
            local list = route.list
            for i = 1, #list do
                list[i].fn(ev, unit, ...)
            end
        end)
        unitRoutes[routeKey] = route
    end
    route.list = with(route.list, entry)
    return true
end

-- Removes fn from every registration of event; an event nothing listens to is unregistered.
function ns.Off(event, fn)
    local list = broad[event]
    if list then
        list = without(list, fn)
        if #list == 0 then
            broad[event] = nil
            pcall(eventFrame.UnregisterEvent, eventFrame, event)
        else
            broad[event] = list
        end
    end
    local emptied = {}
    for routeKey, route in pairs(unitRoutes) do
        if route.event == event then
            route.list = without(route.list, fn)
            if #route.list == 0 then
                emptied[#emptied + 1] = routeKey
            end
        end
    end
    for _, routeKey in ipairs(emptied) do
        local route = unitRoutes[routeKey]
        unitRoutes[routeKey] = nil
        pcall(route.frame.UnregisterEvent, route.frame, event)
    end
end

----------------------------------------------------------------------------------
-- the combat queue
--
-- Protected frames cannot be moved, sized, shown or reconfigured in combat (CF-079). AfterCombat
-- runs fn now when that is allowed, else once when combat ends; a key replaces an earlier request
-- with the same key, so a burst of changes applies once. Lockdown has not begun while
-- PLAYER_REGEN_DISABLED's handlers run (CF-074), and a reload in combat sees no
-- PLAYER_REGEN_DISABLED, so either counts. This file loads first, so the flag changes before any
-- other file's handlers for those events run.
----------------------------------------------------------------------------------

local queued, queueOrder = {}, {}
local fighting = false

function ns.InCombat()
    if fighting then
        return true
    end
    local lockdown = InCombatLockdown
    return lockdown ~= nil and lockdown() == true
end

function ns.AfterCombat(key, fn)
    if not ns.InCombat() then
        run("AfterCombat " .. tostring(key), fn)
        return true
    end
    if not queued[key] then
        queueOrder[#queueOrder + 1] = key
    end
    queued[key] = fn
    return false
end

ns.On("PLAYER_REGEN_DISABLED", function()
    fighting = true
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    fighting = false
    local keys = queueOrder
    queueOrder = {}
    for _, key in ipairs(keys) do
        local fn = queued[key]
        queued[key] = nil
        if fn then
            run("AfterCombat " .. tostring(key), fn)
        end
    end
end)

----------------------------------------------------------------------------------
-- blocked and forbidden actions
--
-- Silent to Lua, so only these events tell (CF-075). They are broadcast for every addon: each is
-- counted in the ledger (a running count to bracket a call with, the last LEDGER of them, a count
-- by addon), and those naming this addon are printed and kept, the first KEPT of them.
----------------------------------------------------------------------------------

local ledger = { count = 0, ring = {}, nextSlot = 1, byAddon = {} }
ns.ledger = ledger
ns.blocked, ns.blockedDropped = {}, 0

local function onBlocked(event, blamed, func)
    local addon = tostring(blamed)
    ledger.count = ledger.count + 1
    ledger.byAddon[addon] = (ledger.byAddon[addon] or 0) + 1
    local clock = GetTime
    ledger.ring[ledger.nextSlot] = {
        event = event, addon = addon, func = tostring(func), inCombat = ns.InCombat(),
        at = clock ~= nil and clock() or nil,
    }
    ledger.nextSlot = ledger.nextSlot % LEDGER + 1
    if blamed ~= addonName then
        return
    end
    if #ns.blocked >= KEPT then
        ns.blockedDropped = ns.blockedDropped + 1
        return
    end
    local text = event .. " " .. tostring(func)
    ns.blocked[#ns.blocked + 1] = text
    ns.Print("|cffff5555" .. text .. "|r")
end

ns.On("ADDON_ACTION_BLOCKED", onBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", onBlocked)

-- Bracket a call with this: a call the client refused raised the count (the ledger's last
-- entries say whom the client named).
function ns.LedgerCount()
    return ledger.count
end

-- The ledger's entries, oldest first.
function ns.LedgerEntries()
    local out = {}
    for i = 0, LEDGER - 1 do
        local entry = ledger.ring[(ledger.nextSlot - 1 + i) % LEDGER + 1]
        if entry then
            out[#out + 1] = entry
        end
    end
    return out
end

----------------------------------------------------------------------------------
-- login
--
-- fn once the client knows who logged in (PLAYER_LOGIN), in the order asked, each guarded; at
-- once if that has happened already.
----------------------------------------------------------------------------------

local loginQueue = {}
local loggedIn = false
do
    local isLoggedIn = IsLoggedIn
    loggedIn = isLoggedIn ~= nil and isLoggedIn() == true
end

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    local list = loginQueue
    loginQueue = {}
    for i, fn in ipairs(list) do
        run("OnLogin#" .. i, fn)
    end
end)

function ns.OnLogin(fn)
    if loggedIn then
        run("OnLogin", fn)
        return
    end
    loginQueue[#loginQueue + 1] = fn
end

----------------------------------------------------------------------------------
-- for the other kit modules: the same functions, which an addon's own code cannot replace
----------------------------------------------------------------------------------

Kit.Init = {
    Print = ns.Print, Printf = ns.Printf, Line = ns.Line, Linef = ns.Linef,
    Guard = ns.Guard, Run = run, RecordError = record, TryPart = ns.TryPart,
    AfterCombat = ns.AfterCombat, InCombat = ns.InCombat,
    On = ns.On, Off = ns.Off, OnLogin = ns.OnLogin,
    Note = ns.Note, Count = ns.Count, Stat = ns.Stat,
}
