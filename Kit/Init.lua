-- gkit Init.lua @ f0ef885: edit gkit, not this copy
-- Init.lua -- gkit's core: output, error containment, the combat queue, events and diagnostics.
--
-- Vendored into <addon>/Kit/ by gkit's tools/sync.lua and listed in the TOC first among the kit's
-- files, right after the addon's own file that sets ns.kit. Every other kit module needs it.
--
-- Reads from ns.kit (all optional but name; each option 0.2.0 added is off until set):
--   name           the addon's name as players see it, in the chat prefix
--   prefixColor    the prefix's colour, six hex digits ("4fa3d1")
--   slash          the addon's command ("/gbars"): named in the terse error line, and in the line
--                  that says a key was switched off ("/gbars rearm")
--   errorsPointer  what the terse error line names instead of slash ("/gthreat status"); false
--                  names nothing
--   printedErrors  how many distinct errors print in full before the terse line (10)
--   keptErrors     how many distinct errors, and own blocked actions, are kept (50)
--   errors = {
--     stack  = true    keep the stack of each kept error (errorStacks), taken where it was thrown
--     record = true    with onError, keep the kit's own record as well, after onError has it
--   }
--   onError        function(key, message, stack): every error the kit catches or is handed goes to
--                  the addon's own log instead of the kit's record (or first, with errors.record):
--                  key is the guard's or TryPart's key, "On <event>" for a refused registration,
--                  nil for RecordError; message is the error as raised, as text, without the key;
--                  stack is a string with errors.stack, else nil
--   disableAfter   a guarded handler's failure budget: nil never disables (gFrames, gBars); a
--                  number disables a key after that many failures until ns.Rearm (gThreat: 2)
--   pinned         { [key] = true }: keys a budget never disables
--   blocked = {
--     announce = false   this addon's blocked actions are not printed
--     keep     = false   nor kept in blocked                (blocked = false: both)
--   }
--   ledger         false: no ledger of every addon's blocked actions (ledger is nil, LedgerCount()
--                  answers nil); with blocked off as well the kit does not listen for them at all
--   combat = { clock = "event" | "lockdown" }   what InCombat() follows, below ("event")
--   events = { quiet = true }   a refused registration goes in failedEvents only, not in the errors
--   export         false: Init's API is on ns.Kit.Init only, nothing of it on ns
--
-- On ns (unless export is false) and on ns.Kit.Init:
--   Print(...), Printf(fmt, ...)    a line with the prefix; Line(...), Linef(fmt, ...) without
--   Guard([key,] fn [, onDisabled]) fn wrapped: an error is recorded and printed, never raised;
--                                   returns whether fn ran without error. A key given is named in
--                                   the recorded message ("key: error"); one left out is generated.
--                                   Guard(fn, key), gbaggy's and gquest's order, works too.
--                                   onDisabled(key) runs once, guarded under "<key>/disabled", when
--                                   the budget switches the key off
--   guardFailures                   key -> failures this session
--   DisabledHandlers(), Rearm([key])  the keys a budget switched off; switch them (or one) on again
--   RecordError(message)            record and print an error caught elsewhere
--   errors, errorOrder, errorsDropped   message -> times seen; the first keptErrors distinct
--                                   messages; how many more distinct ones were only counted
--   errorStacks                     message -> its stack, with errors.stack
--   TryPart(key, what, fn, ...)     an optional part: its error is recorded and noted once, and
--                                   nil comes back instead of fn's result
--   AfterCombat(key, fn [, opts])   fn now when out of combat (returns true), else once when
--                                   combat ends (returns false); a key replaces an earlier request.
--                                   opts.fightBegins (or opts true): queued all the same, for a
--                                   caller in a PLAYER_REGEN_DISABLED handler, where neither the
--                                   lockdown (CF-074) nor the order of the handlers can be counted on
--   InCombat()                      clock "event": true from PLAYER_REGEN_DISABLED to
--                                   PLAYER_REGEN_ENABLED, or while the lockdown is up. Clock
--                                   "lockdown": InCombatLockdown() as last read -- at load, at each
--                                   regen event, and every frame after one until it answers what
--                                   the event said
--   OnCombatChange(fn)              fn(true | false), guarded, when InCombat()'s answer changes
--   On(event, fn [, unit1, unit2])  fn(event, ...) on each event; with units, only for those units
--   On(event, fn, opts)             the same, with opts.unit1 and opts.unit2; opts.owner keys the
--                                   handler "<owner>/<event>#n" (n never given out twice), which
--                                   names its errors and lets Off remove it by owner; opts.quiet
--                                   records a refusal in failedEvents only. A function is never
--                                   added twice to an event this way. Returns whether registered
--   Off(event, fn | owner), OffOwner(owner)   remove handlers; each returns how many
--   IsRegistered(event), Registry() event -> "ok", or why not, for every event registered or refused
--   OnLogin(fn)
--   failedEvents                    event -> why it is not delivered
--   blocked, blockedDropped         this addon's blocked and forbidden actions, the first kept
--   ledger, LedgerCount(), LedgerEntries()  every addon's: a count, the last 50, counts by addon
--   Note([key,] ok, text), NotesFor(key), notes   status notes (ok: true, false or nil)
--   Count(key [, n]), counts, Stat(key, what), stats   counters for status
-- On ns.Kit.Init only: Run(key, fn, ...) -> ok, fn's results (fn now, guarded under key, the key
-- not named in the message, nothing built for the call); ErrorsDropped(), BlockedDropped(); and
-- exported, keepsErrors and keepsBlocked, which Kit/Report.lua reads.
--
-- The kit's own code calls the functions and tables defined here, never what is on ns: an addon
-- may put a Print, an InCombat or an errors table of its own there without changing the kit.
--
-- Client facts relied on (gkit's facts/forever-client-facts.md): Lua errors are hidden by default
-- and only about 100 a session reach a handler (CF-140), so errors are printed and budgeted;
-- xpcall passes extra arguments (CF-141), so a guarded call builds no closure, and its handler
-- runs where the error was raised, before the stack unwinds, which is where a stack is taken;
-- registering an unknown event throws (CF-048), so registration is under pcall; the combat log is
-- closed and registering it is forbidden (CF-076), so On refuses it; InCombatLockdown() is false
-- inside PLAYER_REGEN_DISABLED, and PLAYER_REGEN_ENABLED comes just after it ends (CF-074), hence
-- the two clocks and fightBegins; a refused protected call is silent to Lua and fires
-- ADDON_ACTION_BLOCKED (CF-075), hence the ledger; protected frames wait out combat (CF-079),
-- hence AfterCombat.
--
-- Assumptions, not in the registry: debugstack(2), called in xpcall's handler, answers the stack
-- from where the error was raised as a string (the shared API audit finds debugstack on 70450,
-- where Blizzard_ScriptErrors calls it, and gquest's and gbaggy's error logs keep its output in
-- play); without it no stack is kept. The kit's frame is the first to register the regen events,
-- so handlers registered through On see the event clock change first; whether another frame's
-- handlers for the same event run before or after is unmeasured, which is what fightBegins is for.

local addonName, ns = ...

local kit = ns.kit
if type(kit) ~= "table" then
    error("gkit: set ns.kit in a file the TOC loads before Kit/Init.lua", 0)
end

local Kit = { version = "0.2.0" }
ns.Kit = Kit

local pcall, xpcall, select, tostring, type, ipairs, pairs = pcall, xpcall, select, tostring, type, ipairs, pairs
local strformat, tconcat, tsort = string.format, table.concat, table.sort

-- A table option of ns.kit, or an empty one when it is not set.
local function settings(name)
    local value = kit[name]
    if value == nil then
        return {}
    end
    if type(value) ~= "table" then
        error("gkit: ns.kit." .. name .. " is a table", 0)
    end
    return value
end

local EXPORT = kit.export ~= false
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

local function Print(...)
    print(PREFIX .. joined(...))
end

local function Printf(fmt, ...)
    print(PREFIX .. strformat(fmt, ...))
end

local function Line(...)
    print(joined(...))
end

local function Linef(fmt, ...)
    print(strformat(fmt, ...))
end

----------------------------------------------------------------------------------
-- errors
--
-- The client's error frame is off by default, so an error is printed: the first PRINTED distinct
-- ones in full, then a terse count for each new one, so a part that keeps breaking in new ways
-- does not fall silent. The first KEPT distinct messages are kept for status and the report; past
-- them new messages are only counted, so a message with a changing name in it cannot grow the
-- list, or the save, for the whole session. An addon with a log of its own has them handed to it
-- instead (onError), or first.
----------------------------------------------------------------------------------

local errorSettings = settings("errors")
local KEEP_STACK = errorSettings.stack == true
local onError = kit.onError
if onError ~= nil and type(onError) ~= "function" then
    error("gkit: ns.kit.onError is a function", 0)
end
local RECORD = errorSettings.record
if RECORD == nil then
    RECORD = onError == nil
end
RECORD = RECORD and true or false

local pointer = kit.errorsPointer
if pointer == nil then
    pointer = kit.slash
end
local POINTER = pointer and (", " .. tostring(pointer)) or ""

local errors, errorOrder, errorStacks = {}, {}, {}
local errorsDropped = 0

-- The kit's own record of one error.
local function keep(message, stack)
    if errors[message] then
        errors[message] = errors[message] + 1
        return
    end
    if #errorOrder >= KEPT then
        errorsDropped = errorsDropped + 1
        if EXPORT then
            ns.errorsDropped = errorsDropped
        end
        return
    end
    errors[message] = 1
    errorOrder[#errorOrder + 1] = message
    if stack ~= nil then
        errorStacks[message] = stack
    end
    if #errorOrder <= PRINTED then
        Print("|cffff5555error|r " .. message)
    else
        Print(strformat("|cffff5555%d errors so far|r%s", #errorOrder, POINTER))
    end
end

-- Every error the kit catches or is handed comes here: to the addon's log, to the kit's record, or
-- to both. label, when given, goes in front of the recorded message ("key: error").
local function report(key, err, label, stack)
    local message = tostring(err)
    local recorded = label and (label .. ": " .. message) or message
    if onError then
        local ok, why = pcall(onError, key, message, stack)
        if not ok then
            -- The addon's log failed: both are kept here rather than lost.
            keep(recorded, stack)
            keep("onError: " .. tostring(why))
            return
        end
    end
    if RECORD then
        keep(recorded, stack)
    end
end

local function RecordError(message)
    report(nil, message, nil, nil)
end

----------------------------------------------------------------------------------
-- error containment
--
-- Everything run from an event, a callback, a click or a timer goes through a guard. A key counts
-- its failures; with ns.kit.disableAfter set, a key that reaches it stops running until
-- ns.Rearm, so one broken call site in a fast loop cannot spend the session's errors (CF-140).
-- The call goes through xpcall with fn's arguments (CF-141): no closure per call, and a stack can
-- be taken in the handler, where the error was raised.
----------------------------------------------------------------------------------

local failures = {}
local DISABLE_AFTER = kit.disableAfter
local pinned = kit.pinned or {}
local said = {}          -- key -> true once its switching off was printed
local generated = 0

local function disabled(key)
    return DISABLE_AFTER ~= nil and not pinned[key] and (failures[key] or 0) >= DISABLE_AFTER
end

local caught             -- the stack catch took for the call that just failed

-- xpcall's handler: the error goes back as it came, so a guarded call sees what pcall gave.
local function catch(err)
    if KEEP_STACK then
        local stackOf = debugstack
        if type(stackOf) == "function" then
            caught = stackOf(2)
        end
    end
    return err
end

-- What a guarded call comes back with: true and fn's results; or false, once the failure is
-- counted and reported and, if it was the key's last, the key switched off.
local function close(key, label, onDisabled, ok, ...)
    if ok then
        return true, ...
    end
    local stack = caught
    caught = nil
    failures[key] = (failures[key] or 0) + 1
    report(key, (...), label, stack)
    if disabled(key) and not said[key] then
        said[key] = true
        Print(strformat("|cffff5555%s disabled for this session|r (%d errors)%s", tostring(key),
            failures[key], kit.slash and (", " .. kit.slash .. " rearm") or ""))
        if onDisabled then
            local hook = tostring(key) .. "/disabled"
            close(hook, hook, nil, xpcall(onDisabled, catch, key))
        end
    end
    return false
end

-- fn(...) under the guard keyed key.
local function call(key, label, onDisabled, fn, ...)
    if disabled(key) then
        return false
    end
    return close(key, label, onDisabled, xpcall(fn, catch, ...))
end

-- label: put in front of the recorded message, or nil for the message as it is.
local function guard(key, fn, label, onDisabled)
    return function(...)
        return (call(key, label, onDisabled, fn, ...))
    end
end

local function newKey(what)
    generated = generated + 1
    return (what or "guard") .. "#" .. generated
end

local function Guard(key, fn, onDisabled)
    if fn == nil and type(key) == "function" then
        return guard(newKey(), key, nil, onDisabled)
    end
    if type(key) == "function" and type(fn) == "string" then
        key, fn = fn, key   -- gbaggy's and gquest's order, Guard(fn, where)
    end
    if key == nil then
        return guard(newKey(), fn, nil, onDisabled)
    end
    return guard(key, fn, tostring(key), onDisabled)
end

-- fn(...) now under a guard keyed key, without naming the key in the message: whether fn ran
-- without error, then what it returned.
local function Run(key, fn, ...)
    return call(key, nil, nil, fn, ...)
end

local function DisabledHandlers()
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
local function Rearm(key)
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

local notes = {}          -- { key = key or nil, ok = true | false | nil, text = "" }, in order
local counts, stats = {}, {}

-- ok: true for "worked", false for "missing or failed", nil for plain information. The key may
-- be left out: Note(ok, text).
local function Note(key, ok, text)
    if text == nil and type(ok) == "string" and (key == nil or type(key) == "boolean") then
        key, ok, text = nil, key, ok
    end
    notes[#notes + 1] = { key = key, ok = ok, text = text }
end

local function NotesFor(key)
    local out = {}
    for _, note in ipairs(notes) do
        if note.key == key then
            out[#out + 1] = note
        end
    end
    return out
end

local function Count(key, n)
    counts[key] = (counts[key] or 0) + (n or 1)
end

local function Stat(key, what)
    local stat = stats[key]
    if not stat then
        stat = {}
        stats[key] = stat
    end
    stat[what] = (stat[what] or 0) + 1
end

-- An optional part (of a frame, a window, a row): one that throws is recorded, noted under key
-- once and left out, and the rest is built all the same. Returns what fn returns, or nil.
local leftOut = {}

local function partDone(key, what, ok, result)
    if ok then
        return result
    end
    local stack = caught
    caught = nil
    report(key, result, nil, stack)
    local id = tostring(key) .. ": " .. tostring(what)
    if not leftOut[id] then
        leftOut[id] = true
        Note(key, false, tostring(what) .. " left out: " .. tostring(result))
    end
    return nil
end

local function TryPart(key, what, fn, ...)
    return partDone(key, what, xpcall(fn, catch, ...))
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

local QUIET = settings("events").quiet == true

local failedEvents = {}

local eventFrame = CreateFrame("Frame")
local broad = {}        -- event -> { { raw = fn, owner = owner, fn = guarded }, ... }
local unitRoutes = {}   -- "event|unit1|unit2" -> { frame, event, unit1, unit2, list }
local ownerSeq = {}     -- "owner/event" -> the last n given out

local function with(list, entry)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    out[#out + 1] = entry
    return out
end

-- The list without fn's entries, or without owner's when fn is nil; and how many went.
local function without(list, fn, owner)
    local out, removed = {}, 0
    for i = 1, #list do
        local entry = list[i]
        if (fn ~= nil and entry.raw == fn) or (fn == nil and entry.owner ~= nil and entry.owner == owner) then
            removed = removed + 1
        else
            out[#out + 1] = entry
        end
    end
    return out, removed
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = broad[event]
    if list then
        for i = 1, #list do
            list[i].fn(event, ...)
        end
    end
end)

local function failed(event, why, quiet)
    if not failedEvents[event] then
        failedEvents[event] = tostring(why)
        if not quiet then
            report("On " .. tostring(event), "could not register " .. tostring(event) .. ": " .. tostring(why), nil, nil)
        end
    end
    return false
end

local handlerCount = 0

-- fn(event, ...) on each event; with units, only for those units (RegisterUnitEvent). Returns
-- whether the event is registered.
local function On(event, fn, unit1, unit2)
    local opts
    if type(unit1) == "table" then
        opts = unit1
        unit1, unit2 = opts.unit1, opts.unit2
    end
    local quiet = QUIET or (opts ~= nil and opts.quiet == true)
    if FORBIDDEN[event] then
        return failed(event, "refused: the client forbids the combat log to addons (gkit CF-076)", quiet)
    end
    local routeKey, route
    if unit1 ~= nil then
        routeKey = strformat("%s|%s|%s", tostring(event), tostring(unit1), tostring(unit2))
        route = unitRoutes[routeKey]
    end
    if opts then
        local list = (unit1 == nil and broad[event]) or (route and route.list) or {}
        for i = 1, #list do
            if list[i].raw == fn then
                return true
            end
        end
    end
    local owner = opts and opts.owner
    local key, label
    if owner ~= nil then
        local base = tostring(owner) .. "/" .. tostring(event)
        local n = (ownerSeq[base] or 0) + 1
        ownerSeq[base] = n
        key = base .. "#" .. n
        label = key
    else
        handlerCount = handlerCount + 1
        key = "On " .. tostring(event) .. "#" .. handlerCount
    end
    local entry = { raw = fn, owner = owner, fn = guard(key, fn, label, nil) }
    if unit1 == nil then
        if not broad[event] then
            local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
            if not ok then
                return failed(event, err, quiet)
            end
            broad[event] = {}
        end
        broad[event] = with(broad[event], entry)
        return true
    end
    if not route then
        local frame = CreateFrame("Frame")
        local ok, err
        if unit2 ~= nil then
            ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit1, unit2)
        else
            ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit1)
        end
        if not ok then
            return failed(event, err, quiet)
        end
        route = { frame = frame, event = event, unit1 = unit1, unit2 = unit2, list = {} }
        local thisRoute = route
        frame:SetScript("OnEvent", function(_, ev, unit, ...)
            if unit ~= thisRoute.unit1 and (thisRoute.unit2 == nil or unit ~= thisRoute.unit2) then
                return
            end
            local list = thisRoute.list
            for i = 1, #list do
                list[i].fn(ev, unit, ...)
            end
        end)
        unitRoutes[routeKey] = route
    end
    route.list = with(route.list, entry)
    return true
end

-- Removes fn, or every handler of owner, from every registration of event; an event nothing
-- listens to any more is unregistered. Returns how many handlers went.
local function Off(event, fnOrOwner)
    if fnOrOwner == nil then
        return 0
    end
    local fn, owner
    if type(fnOrOwner) == "function" then
        fn = fnOrOwner
    else
        owner = fnOrOwner
    end
    local removed = 0
    local list = broad[event]
    if list then
        local n
        list, n = without(list, fn, owner)
        removed = removed + n
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
            local n
            route.list, n = without(route.list, fn, owner)
            removed = removed + n
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
    return removed
end

-- Every handler of owner, from every event. Returns how many went.
local function OffOwner(owner)
    if owner == nil then
        return 0
    end
    local events = {}
    for event in pairs(broad) do
        events[event] = true
    end
    for _, route in pairs(unitRoutes) do
        events[route.event] = true
    end
    local removed = 0
    for event in pairs(events) do
        removed = removed + Off(event, owner)
    end
    return removed
end

local function IsRegistered(event)
    if broad[event] then
        return true
    end
    for _, route in pairs(unitRoutes) do
        if route.event == event then
            return true
        end
    end
    return false
end

-- event -> "ok" for each event registered now, or why not for each one refused. Registration is
-- not delivery (CF-049): this says what was tried, not what arrives.
local function Registry()
    local out = {}
    for event in pairs(broad) do
        out[event] = "ok"
    end
    for _, route in pairs(unitRoutes) do
        out[route.event] = "ok"
    end
    for event, why in pairs(failedEvents) do
        if out[event] == nil then
            out[event] = why
        end
    end
    return out
end

----------------------------------------------------------------------------------
-- the combat queue and the clock
--
-- Protected frames cannot be moved, sized, shown or reconfigured in combat (CF-079). AfterCombat
-- runs fn now when that is allowed, else once when combat ends; a key replaces an earlier request
-- with the same key, so a burst of changes applies once.
--
-- The lockdown has not begun while PLAYER_REGEN_DISABLED's handlers run (CF-074). The event clock
-- counts the event as combat, and a reload in combat, which sees no PLAYER_REGEN_DISABLED, by the
-- lockdown: the answer AfterCombat wants, as early as there is one. The lockdown clock answers
-- only what InCombatLockdown() says, the answer something that measures protection wants (gThreat):
-- it reads it at load, at each regen event, and every frame after one until it says what the event
-- pointed at. AfterCombat asks the lockdown as well, so the frame the poll lags never runs work it
-- should hold. A caller that knows the fight is beginning says so (fightBegins): its work waits
-- whichever handler ran first.
----------------------------------------------------------------------------------

local CLOCK = settings("combat").clock or "event"
if CLOCK ~= "event" and CLOCK ~= "lockdown" then
    error('gkit: ns.kit.combat.clock is "event" or "lockdown"', 0)
end

local queued, queueOrder = {}, {}
local fighting = false   -- the event clock: PLAYER_REGEN_DISABLED seen, PLAYER_REGEN_ENABLED not yet
local locked = false     -- the lockdown clock: InCombatLockdown() as last read
local watchers = {}

local function lockdownUp()
    local lockdown = InCombatLockdown
    return lockdown ~= nil and lockdown() == true
end

local function InCombat()
    if CLOCK == "lockdown" then
        return locked
    end
    return fighting or lockdownUp()
end

-- Whether protected frames have to wait.
local function mustWait()
    if CLOCK == "lockdown" then
        return locked or lockdownUp()
    end
    return InCombat()
end

local function OnCombatChange(fn)
    local out = {}
    for i = 1, #watchers do
        out[i] = watchers[i]
    end
    out[#out + 1] = fn
    watchers = out
end

local function announce(state)
    local list = watchers
    for i = 1, #list do
        call("OnCombatChange#" .. i, nil, nil, list[i], state)
    end
end

local function runQueue()
    local keys = queueOrder
    queueOrder = {}
    for _, key in ipairs(keys) do
        local fn = queued[key]
        queued[key] = nil
        if fn then
            call("AfterCombat " .. tostring(key), nil, nil, fn)
        end
    end
end

local function AfterCombat(key, fn, opts)
    local fightBegins = opts == true or (type(opts) == "table" and opts.fightBegins == true)
    if not fightBegins and not mustWait() then
        call("AfterCombat " .. tostring(key), nil, nil, fn)
        return true
    end
    if not queued[key] then
        queueOrder[#queueOrder + 1] = key
    end
    queued[key] = fn
    return false
end

if CLOCK == "event" then
    On("PLAYER_REGEN_DISABLED", function()
        local was = InCombat()
        fighting = true
        if not was then
            announce(true)
        end
    end)

    On("PLAYER_REGEN_ENABLED", function()
        local was = InCombat()
        fighting = false
        runQueue()
        if was and not InCombat() then
            announce(false)
        end
    end)
else
    locked = lockdownUp()
    local heading = false   -- what the last regen event said the lockdown is heading for
    local poller = CreateFrame("Frame")
    poller:Hide()

    local function observe(now)
        if now == locked then
            return
        end
        locked = now
        if not now then
            runQueue()
        end
        announce(now)
    end

    poller:SetScript("OnUpdate", function(self)
        local now = lockdownUp()
        if now == heading then
            self:Hide()
        end
        observe(now)
    end)

    On("PLAYER_REGEN_DISABLED", function()
        heading = true
        observe(lockdownUp())
        poller:Show()
    end)

    -- A fight over within one frame never showed the poll a lockdown; fightBegins work still runs.
    On("PLAYER_REGEN_ENABLED", function()
        heading = false
        local now = lockdownUp()
        observe(now)
        if now then
            poller:Show()
        else
            poller:Hide()
            runQueue()
        end
    end)
end

----------------------------------------------------------------------------------
-- blocked and forbidden actions
--
-- Silent to Lua, so only these events tell (CF-075). They are broadcast for every addon: each is
-- counted in the ledger (a running count to bracket a call with, the last LEDGER of them, a count
-- by addon), and those naming this addon are printed and kept, the first KEPT of them. An addon
-- with a watcher of its own turns either off (ns.kit.blocked, ns.kit.ledger).
----------------------------------------------------------------------------------

local blockedSettings = kit.blocked == false and { announce = false, keep = false } or settings("blocked")
local ANNOUNCE = blockedSettings.announce ~= false
local KEEP_BLOCKED = blockedSettings.keep ~= false

local ledger
if kit.ledger ~= false then
    ledger = { count = 0, ring = {}, nextSlot = 1, byAddon = {} }
end
local blocked, blockedDropped, ownBlocked = {}, 0, 0

local function onBlocked(event, blamed, func)
    if ledger then
        local addon = tostring(blamed)
        ledger.count = ledger.count + 1
        ledger.byAddon[addon] = (ledger.byAddon[addon] or 0) + 1
        local clock = GetTime
        ledger.ring[ledger.nextSlot] = {
            event = event, addon = addon, func = tostring(func), inCombat = InCombat(),
            at = clock ~= nil and clock() or nil,
        }
        ledger.nextSlot = ledger.nextSlot % LEDGER + 1
    end
    if blamed ~= addonName or not (ANNOUNCE or KEEP_BLOCKED) then
        return
    end
    if ownBlocked >= KEPT then
        blockedDropped = blockedDropped + 1
        if EXPORT then
            ns.blockedDropped = blockedDropped
        end
        return
    end
    ownBlocked = ownBlocked + 1
    local text = event .. " " .. tostring(func)
    if KEEP_BLOCKED then
        blocked[#blocked + 1] = text
    end
    if ANNOUNCE then
        Print("|cffff5555" .. text .. "|r")
    end
end

if ledger or ANNOUNCE or KEEP_BLOCKED then
    On("ADDON_ACTION_BLOCKED", onBlocked)
    On("ADDON_ACTION_FORBIDDEN", onBlocked)
end

-- Bracket a call with this: a call the client refused raised the count (the ledger's last
-- entries say whom the client named). Nil without a ledger.
local function LedgerCount()
    if not ledger then
        return nil
    end
    return ledger.count
end

-- The ledger's entries, oldest first.
local function LedgerEntries()
    local out = {}
    if not ledger then
        return out
    end
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

On("PLAYER_LOGIN", function()
    loggedIn = true
    local list = loginQueue
    loginQueue = {}
    for i, fn in ipairs(list) do
        call("OnLogin#" .. i, nil, nil, fn)
    end
end)

local function OnLogin(fn)
    if loggedIn then
        call("OnLogin", nil, nil, fn)
        return
    end
    loginQueue[#loginQueue + 1] = fn
end

----------------------------------------------------------------------------------
-- the API: on ns.Kit.Init, where the kit's modules find it and an addon's own code cannot
-- replace it, and on ns unless ns.kit.export is false
----------------------------------------------------------------------------------

Kit.Init = {
    Print = Print, Printf = Printf, Line = Line, Linef = Linef,
    Guard = Guard, Run = Run, RecordError = RecordError, TryPart = TryPart,
    DisabledHandlers = DisabledHandlers, Rearm = Rearm,
    AfterCombat = AfterCombat, InCombat = InCombat, OnCombatChange = OnCombatChange,
    On = On, Off = Off, OffOwner = OffOwner, IsRegistered = IsRegistered, Registry = Registry,
    OnLogin = OnLogin,
    Note = Note, NotesFor = NotesFor, Count = Count, Stat = Stat,
    LedgerCount = LedgerCount, LedgerEntries = LedgerEntries,
    ErrorsDropped = function() return errorsDropped end,
    BlockedDropped = function() return blockedDropped end,
    errors = errors, errorOrder = errorOrder, errorStacks = errorStacks, guardFailures = failures,
    failedEvents = failedEvents, blocked = blocked, ledger = ledger,
    notes = notes, counts = counts, stats = stats,
    exported = EXPORT, keepsErrors = RECORD, keepsBlocked = KEEP_BLOCKED,
}

if EXPORT then
    ns.addonName = addonName
    ns.Print, ns.Printf, ns.Line, ns.Linef = Print, Printf, Line, Linef
    ns.errors, ns.errorOrder, ns.errorsDropped, ns.errorStacks = errors, errorOrder, errorsDropped, errorStacks
    ns.RecordError = RecordError
    ns.guardFailures = failures
    ns.Guard, ns.DisabledHandlers, ns.Rearm = Guard, DisabledHandlers, Rearm
    ns.notes, ns.counts, ns.stats = notes, counts, stats
    ns.Note, ns.NotesFor, ns.Count, ns.Stat, ns.TryPart = Note, NotesFor, Count, Stat, TryPart
    ns.failedEvents = failedEvents
    ns.On, ns.Off, ns.OffOwner, ns.IsRegistered, ns.Registry = On, Off, OffOwner, IsRegistered, Registry
    ns.InCombat, ns.AfterCombat, ns.OnCombatChange = InCombat, AfterCombat, OnCombatChange
    ns.ledger, ns.blocked, ns.blockedDropped = ledger, blocked, blockedDropped
    ns.LedgerCount, ns.LedgerEntries = LedgerCount, LedgerEntries
    ns.OnLogin = OnLogin
end
