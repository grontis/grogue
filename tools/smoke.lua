-- tools/smoke.lua -- load gRogue against tools/stub_wow.lua and check what it does: the
-- non-rogue path, settings over a save and saves it can't use, the bar's layout and its
-- secret count, dragging, when the bar shows, the settings panel, /grogue, the addon
-- compartment, and clients without the interpolation enum or a member of it, without
-- GetComboPoints or without the vehicle events.
--
--   luajit tools/smoke.lua .        (or tools/smoke.sh)
--   SMOKE_VERBOSE=1 ... also prints the addon's chat output
--
-- A pass here means the logic holds against the stub. It says nothing about how anything
-- looks, or about a client behaviour the stub does not model: those need a session.

local ADDON_DIR = arg[1] or "."
local HERE = arg[0]:match("^(.*)/[^/]*$") or "."
local say = print   -- the stub replaces print to capture the addon's chat
local H = assert(loadfile(HERE .. "/stub_wow.lua"))(ADDON_DIR)
local print = say

local failures, passes = 0, 0
local function check(cond, msg)
    if cond then
        passes = passes + 1
        print("PASS " .. msg)
    else
        failures = failures + 1
        print("FAIL " .. msg)
    end
end

-- Chat this session, and the errors in it not yet looked at.
local errorsSeen = 0
local function said(pattern)
    for _, line in ipairs(H.printed) do
        if line:find(pattern) then
            return true
        end
    end
    return false
end
local function newErrors()
    local out = {}
    for i = errorsSeen + 1, #H.printed do
        local line = H.printed[i]
        if line:find("error") or line:find("could not") then
            out[#out + 1] = line
        end
    end
    errorsSeen = #H.printed
    return out
end
local function noErrors(msg)
    local e = newErrors()
    check(#e == 0, msg .. (#e > 0 and (" (" .. table.concat(e, " | ") .. ")") or ""))
end

-- A new session over whatever gRogueDB holds, up to and including ADDON_LOADED.
local function session()
    local ns = H.load()
    errorsSeen = 0
    H.fire("ADDON_LOADED", "gRogue")
    return ns
end

-- The bar's pips, in order: the frames parented to it.
local function pipsOf(frame)
    local pips = {}
    for _, f in ipairs(H.created) do
        if f._parent == frame and f._type == "Frame" then
            pips[#pips + 1] = f
        end
    end
    return pips
end

-- Every pip's two bars, the reveal first.
local function barsOf(pips)
    local bars = {}
    for _, pip in ipairs(pips) do
        bars[#bars + 1] = pip.reveal
        bars[#bars + 1] = pip.bar
    end
    return bars
end

-- Whether every bar holds a secret (value "secret") or the given number.
local function allBars(pips, value)
    for _, bar in ipairs(barsOf(pips)) do
        if value == "secret" then
            if not bar._secret then
                return false
            end
        elseif bar._secret or bar._value ~= value then
            return false
        end
    end
    return true
end

-- Whether every pip's reveal bar got ease and its visible bar snap as SetValue's
-- interpolation; with neither, whether SetValue got the count alone.
local function modes(pips, ease, snap)
    local args = ease == nil and 1 or 2
    for _, pip in ipairs(pips) do
        if pip.reveal._args ~= args or pip.bar._args ~= args
            or pip.reveal._interp ~= ease or pip.bar._interp ~= snap then
            return false
        end
    end
    return true
end

-- The panel's control, or button, whose label reads text.
local function control(text)
    for _, f in ipairs(H.created) do
        for _, region in ipairs(f._regions or {}) do
            if region._type == "FontString" and region._text == text then
                return f
            end
        end
    end
end

local function near(a, b)
    return type(a) == "number" and math.abs(a - b) < 1e-9
end

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

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
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

------------------------------------------------------------------------------ a warrior
print("== a warrior")
gRogueDB = nil
playerClass = "WARRIOR"
local ns = H.load()
H.fire("ADDON_LOADED", "SomeOtherAddon")
check(ns.db == nil, "another addon's ADDON_LOADED is not ours")
H.fire("ADDON_LOADED", "gRogue")
check(ns.db ~= nil and ns.db == gRogueDB and ns.db.scale == 1 and ns.db.locked == true, "settings made from the defaults")
check(ns.frame == nil and gRogueComboFrame == nil, "no bar")
SlashCmdList.GROGUE("")
check(said("only active on rogues"), "/grogue says it is only active on rogues")
gRogue_OnAddonCompartmentEnter("gRogue", H.loose("menuButton"))
check(GameTooltip._lines[2] == "Only active on rogues", "so does the compartment's tooltip")
gRogue_OnAddonCompartmentClick()
check(gRogueOptions == nil, "and a click opens no panel")
noErrors("no errors as a warrior")

------------------------------------------------------------------------------ a new rogue
print("== a new rogue, no target")
gRogueDB = nil
playerClass = "ROGUE"
comboPoints = 0
ns = session()
local f = ns.frame
check(f ~= nil and f == gRogueComboFrame and f._parent == UIParent, "the bar exists, on UIParent")
local pips = pipsOf(f)
check(#pips == 5, "five pips (" .. #pips .. ")")
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors at PLAYER_ENTERING_WORLD")
local at = f._points.CENTER
check(at and at.rel == UIParent and at.relPoint == "CENTER" and at.x == 0 and at.y == -180
    and f._scale == 1 and f._alpha == 1, "at the default spot, scale 1, opaque")
check(f._width == 5 * 30 + 4 * 4 and f._height == 12, "sized for five 30 x 12 pips 4 apart")
local placed = true
for i, pip in ipairs(pips) do
    local tl = pip._points.TOPLEFT
    placed = placed and tl ~= nil and tl.rel == f and tl.x == (i - 1) * 34 and tl.y == 0
        and pip._width == 30 and pip._height == 12
end
check(placed, "pips left to right, 34 px apart")
check(f:IsShown() and f._mouse == false and not f.mover:IsShown() and not f.moverLabel:IsShown(),
    "locked: shown, no mouse, no mover")
check(allBars(pips, 0), "a count of 0 reaches every bar")
check(modes(pips, 1, 0), "smooth fill (the default): every reveal bar eases, every visible bar snaps")
local structure = true
for k, pip in ipairs(pips) do
    local clip = pip.bar._parent
    structure = structure and pip.reveal._parent == pip and clip._parent == pip
        and clip._clips == true and clip._allPoints == pip.reveal._fill
        and pip.reveal._points.TOPLEFT.rel == pip and pip.bar._points.TOPLEFT.rel == pip
        and pip.reveal._min == k - 1 and pip.reveal._max == k and pip.bar._min == k - 1 and pip.bar._max == k
        and pip.reveal._barColor[4] == 0
end
check(structure, "each pip: an invisible reveal bar, the visible bar in a clip on the reveal's fill, "
    .. "both anchored to the pip, spanning k-1 to k")
local edge = pips[1].border
check(edge.left._width == 1 and edge.top._height == 1 and edge.left:IsShown()
    and pips[1].bar._points.TOPLEFT.x == 1 and pips[1].bar._points.TOPLEFT.y == -1,
    "a 1 px border inside the pip, the bars inset by it")
check(pips[1].bar._fill._texture == ns.textures.flat.path and near(pips[1].bar._barColor[2], 0.82)
    and pips[1].bg._color[4] == 0.5, "flat texture, gold fill, empty at half opacity")
noErrors("no errors for a new rogue")

------------------------------------------------------------------------------ a prior save
print("== a rogue with a prior save")
gRogueDB = {
    x = 40, y = -100, scale = 2, locked = false, border = false, smooth = false,
    texture = "nope", pipColors = { { r = 0.1, g = 0.1, b = 0.1 } }, bogus = 7,
}
ns = session()
local db = ns.db
check(db == gRogueDB and db.x == 40 and db.y == -100 and db.scale == 2, "saved values kept")
check(db.locked == false and db.border == false and db.smooth == false,
    "a saved false is kept, not taken for a missing value")
check(db.point == "CENTER" and db.spacing == 4 and db.hideOutOfCombat == false, "missing settings filled from the defaults")
check(db.pipColors[1].r == 0.1 and db.pipColors[2].r == 1 and near(db.pipColors[2].g, 0.75),
    "point colours merged one by one")
check(db.fillColor ~= ns.defaults.fillColor and db.pipColors[2] ~= ns.defaults.pipColors[2],
    "colour tables are copies, never the defaults' own")
check(db.bogus == 7, "a key this version does not know is left alone")
f = ns.frame
pips = pipsOf(f)
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors at PLAYER_ENTERING_WORLD")
check(f._points.CENTER.x == 20 and f._points.CENTER.y == -50 and f._scale == 2,
    "the saved offset divided by the scale (40, -100 at scale 2 -> 20, -50)")
check(f:IsShown() and f._mouse == true and f.mover:IsShown() and f.moverLabel:IsShown(),
    "unlocked: shown, mouse on, mover and label shown")
check(allBars(pips, 3), "while unlocked every bar previews 3 points")
check(modes(pips, 0, 0), "smooth fill off: both bars snap")
check(not pips[1].border.left:IsShown() and pips[1].bar._points.TOPLEFT.x == 0, "no border: hidden, the bars not inset")
check(pips[1].bar._fill._texture == ns.textures.flat.path, "a texture this version does not know draws as flat")
check(db.texture == "flat" and said("reset saved settings this version can't use: texture%.$"),
    "and goes back to the default at load, which is said")
ns:Set("smooth", true)
check(modes(pips, 1, 0), "smooth fill on: the reveal eases, the bar snaps")
ns:Set("border", true)
check(pips[1].border.left:IsShown() and pips[1].bar._points.TOPLEFT.x == 1, "border on: shown, the bars inset")

------------------------------------------------------------------------------ drag
print("== drag")
f._dragTo = { "TOPLEFT", UIParent, "BOTTOMLEFT", 100, 200 }
f._OnDragStart(f, "LeftButton")
check(f._moving == true, "a drag moves the bar")
f._OnDragStop(f)
check(f._moving == false and db.point == "TOPLEFT" and db.relativePoint == "BOTTOMLEFT" and db.x == 200 and db.y == 400,
    "the drop saves the point and the offset times the scale (100, 200 at scale 2 -> 200, 400)")
f._dragTo = nil
ns:Set("scale", 1)
check(f._points.TOPLEFT.x == 200 and f._points.TOPLEFT.y == 400 and f._points.TOPLEFT.relPoint == "BOTTOMLEFT"
    and f._scale == 1, "scale 1: the same place, offset 200, 400")
ns:Set("scale", 0.5)
check(f._points.TOPLEFT.x == 400 and f._points.TOPLEFT.y == 800 and f._scale == 0.5, "scale 0.5: the same place, offset 400, 800")
ns:Set("scale", 1)
SlashCmdList.GROGUE("lock")
check(db.locked == true and f._mouse == false and not f.mover:IsShown() and said("r: locked%.$"),
    "/grogue lock: mouse off, mover hidden, and says so")
noErrors("no errors dragging")

------------------------------------------------------------------------------ secrets
print("== the count as a secret")
comboPoints = "secret"
targetExists = true
H.fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
check(allBars(pips, "secret"), "a secret count reaches all ten bars' SetValue")
noErrors("nothing compares it, tests it or does arithmetic with it")
H.fire("PLAYER_TARGET_CHANGED")
check(allBars(pips, "secret"), "a target change reads it again")
noErrors("no errors at a target change")
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors in a full refresh")
check(#H.leaks == 0 and #H.readBacks == 0, "it went to SetValue and nowhere else, and no bar was read back ("
    .. table.concat(H.leaks, ", ") .. table.concat(H.readBacks, ", ") .. ")")
comboPoints = 4
H.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
check(allBars(pips, 4), "a plain count reaches every bar too")
check(H.calls.UnitPower == 0, "the count is GetComboPoints', not UnitPower's, while the client has it")

------------------------------------------------------------------------------ visibility
print("== when the bar shows")
-- Every combination of locked, the two hide settings, a target, combat and a vehicle.
local wrong = {}
for case = 0, 63 do
    local function on(n)
        return math.floor(case / 2 ^ n) % 2 == 1
    end
    local locked, needTarget, needCombat, target, combat, vehicle = on(0), on(1), on(2), on(3), on(4), on(5)
    ns:Set("locked", locked)
    ns:Set("hideWithoutTarget", needTarget)
    ns:Set("hideOutOfCombat", needCombat)
    targetExists = target
    H.fire("PLAYER_TARGET_CHANGED")
    H.fire(combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    inVehicle = vehicle
    H.fire(vehicle and "UNIT_ENTERED_VEHICLE" or "UNIT_EXITED_VEHICLE", "player")
    local want = not locked or (not vehicle and (not needTarget or target) and (not needCombat or combat))
    if f:IsShown() ~= want or f.mover:IsShown() ~= not locked or f._mouse ~= not locked then
        wrong[#wrong + 1] = ("locked %s, hide without target %s, hide out of combat %s, target %s, combat %s, vehicle %s")
            :format(tostring(locked), tostring(needTarget), tostring(needCombat), tostring(target),
                tostring(combat), tostring(vehicle))
    end
end
check(#wrong == 0, "shown while unlocked; otherwise hidden in a vehicle and as the target and combat settings say: "
    .. "64 cases" .. (#wrong > 0 and (" (wrong: " .. table.concat(wrong, "; ") .. ")") or ""))
ns:Set("locked", true)
ns:Set("hideWithoutTarget", false)
ns:Set("hideOutOfCombat", false)
targetExists = true
H.fire("PLAYER_TARGET_CHANGED")
H.fire("PLAYER_REGEN_ENABLED")
inVehicle = false
H.fire("UNIT_EXITED_VEHICLE", "player")
H.fire("UNIT_ENTERED_VEHICLE", "party1")
check(f:IsShown(), "a party member's vehicle changes nothing")
noErrors("no errors in the visibility cases")

------------------------------------------------------------------------------ layout
print("== layout")
ns:Set("orientation", "VERTICAL")
ns:Set("reverse", true)
check(f._width == 30 and f._height == 5 * 12 + 4 * 4, "vertical: one pip wide, five high")
check(pips[1]._points.BOTTOMLEFT.y == 4 * 16 and pips[5]._points.BOTTOMLEFT.y == 0, "vertical, reversed: pip 1 at the top")
check(pips[1].bar._orientation == "VERTICAL" and pips[1].bar._reverse == true
    and pips[1].reveal._orientation == "VERTICAL" and pips[1].reveal._reverse == true,
    "both bars vertical and reversed, so the clip grows over the fill")
ns:Set("reverse", false)
check(pips[1]._points.BOTTOMLEFT.y == 0 and pips[5]._points.BOTTOMLEFT.y == 64, "vertical: pip 1 at the bottom")
ns:Set("orientation", "HORIZONTAL")
ns:Set("reverse", true)
check(pips[1]._points.TOPLEFT.x == 136 and pips[5]._points.TOPLEFT.x == 0, "horizontal, reversed: pip 1 at the right")
ns:Set("reverse", false)
ns:Set("pipWidth", 4)
ns:Set("pipHeight", 4)
ns:Set("borderSize", 6)
check(pips[1].border.left._width == 1 and pips[1].bar._points.TOPLEFT.x == 1,
    "a 6 px border in a 4 px pip clamps to 1, leaving a pixel of fill")
ns:Set("pipWidth", 30)
ns:Set("pipHeight", 12)
check(pips[1].border.left._width == 5, "in a 30 x 12 pip it clamps to 5")
ns:Set("borderSize", 1)
ns:Set("usePipColors", true)
check(pips[1].bar._barColor[1] == 0.1 and pips[2].bar._barColor[1] == 1 and near(pips[2].bar._barColor[2], 0.75),
    "a colour for each point")
ns:Set("usePipColors", false)
check(pips[2].bar._barColor[1] == 1 and near(pips[2].bar._barColor[2], 0.82), "one fill colour again")
ns:Set("texture", "raid")
check(pips[3].bar._fill._texture == ns.textures.raid.path, "the chosen texture")
ns:Set("alpha", 0.5)
ns:Set("emptyAlpha", 0.25)
check(f._alpha == 0.5 and pips[1].bg._color[4] == 0.25, "opacity and empty opacity")
ns:Set("texture", "flat")
ns:Set("alpha", 1)
ns:Set("emptyAlpha", 0.5)
noErrors("no errors in layout")

------------------------------------------------------------------------------ the panel
print("== the settings panel")
local function last()
    return H.printed[#H.printed] or ""
end
SlashCmdList.GROGUE("config")
local panel = gRogueOptions
check(panel ~= nil and panel:IsShown(), "/grogue config opens it")
check(UISpecialFrames[1] == "gRogueOptions", "Escape closes it")
noErrors("no errors building it")
local lock = control("Lock position")
check(lock ~= nil and lock.kind == "check" and lock.checked == true, "the lock check shows the setting")
lock:Click()
check(db.locked == false and f.mover:IsShown(), "unticking it unlocks the bar")
lock:Click()
check(db.locked == true and not f.mover:IsShown(), "ticking it locks the bar again")
local scale = control("Scale")
check(scale ~= nil and scale.slider._min == 50 and scale.slider._max == 200 and scale.slider._value == 100,
    "the scale slider runs 50 to 200 percent and shows 100")
scale.slider:SetValue(152)
check(db.scale == 1.5 and f._scale == 1.5, "dragged to 152, it snaps to its 5 percent step: scale 1.5")
local orientation = control("Orientation")
orientation.field:Click()
check(orientation:IsOpen(), "a click opens the orientation list")
orientation.items[2]:Click()
check(db.orientation == "VERTICAL" and not orientation:IsOpen() and orientation.text._text == "Vertical",
    "choosing Vertical sets it and closes the list")
orientation.field:Click()
orientation.items[1]:Click()
check(db.orientation == "HORIZONTAL", "and back to Horizontal")
check(control("Smooth fill") ~= nil, "smooth fill is on offer")
-- A slider runs from end to end of its setting's limits, and a dropdown offers exactly its
-- setting's list: what a save is held to (GR-M2).
local spans = true
for label, spec in pairs({
    ["Point width"] = { "pipWidth", 1 }, ["Point height"] = { "pipHeight", 1 }, Spacing = { "spacing", 1 },
    Scale = { "scale", 100 }, Opacity = { "alpha", 100 }, ["Empty opacity"] = { "emptyAlpha", 100 },
    ["Border size"] = { "borderSize", 1 },
}) do
    local s, limits = control(label), ns.limits and ns.limits[spec[1]]
    spans = spans and s ~= nil and limits ~= nil
        and near(s.slider._min, limits[1] * spec[2]) and near(s.slider._max, limits[2] * spec[2])
end
check(spans, "each slider spans its setting's limits")
local offers = true
for label, key in pairs({ Orientation = "orientation", Texture = "texture" }) do
    local d, choices = control(label), ns.choices and ns.choices[key]
    offers = offers and d ~= nil and choices ~= nil and #d.items == #choices
    for i, item in ipairs(offers and d.items or {}) do
        offers = offers and item.option == choices[i]
    end
end
check(offers, "each dropdown offers its setting's list")

local swatch = control("Filled colour")
check(swatch ~= nil and swatch.kind == "swatch", "the fill colour swatch")
swatch:Click()
local info = ColorPickerFrame.info
check(ColorPickerFrame:IsShown() and info.r == 1 and near(info.g, 0.82) and info.b == 0,
    "a click opens the colour picker on the fill colour")
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0, 0, 1
info.swatchFunc()
check(db.fillColor.r == 0 and db.fillColor.b == 1 and pips[1].bar._barColor[3] == 1,
    "picking blue writes it into the setting and redraws")
ns:ResetSettings()
check(not ColorPickerFrame:IsShown() and db.fillColor.r == 1 and near(db.fillColor.g, 0.82) and db.fillColor.b == 0,
    "a reset with the picker open closes it and restores the colour")
check(last():find("settings reset to defaults") ~= nil, "and says so")
check(db.scale == 1 and scale.slider._value == 100, "the panel shows the defaults after a reset")
swatch:Click()
ColorPickerFrame.r, ColorPickerFrame.g, ColorPickerFrame.b = 0, 1, 0
ColorPickerFrame.info.swatchFunc()
check(db.fillColor.g == 1, "picking green")
ColorPickerFrame.info.cancelFunc()
check(db.fillColor.r == 1 and near(db.fillColor.g, 0.82) and db.fillColor.b == 0,
    "cancel puts back the colour the picker opened on")
ColorPickerFrame:Hide()

scale.slider:SetValue(150)
control("Reset all"):Click()
check(db.scale == 1 and scale.slider._value == 100 and last():find("settings reset to defaults") ~= nil,
    "Reset all restores the defaults, and the panel shows them")
control("x"):Click()
check(not panel:IsShown(), "the x closes the panel")
SlashCmdList.GROGUE("")
check(panel:IsShown(), "/grogue opens it again")
SlashCmdList.GROGUE("")
check(not panel:IsShown(), "and closes it")
noErrors("no errors in the panel")

------------------------------------------------------------------------------ /grogue
print("== /grogue")
SlashCmdList.GROGUE("unlock")
check(db.locked == false and f.mover:IsShown() and last():find("unlocked%. Drag to move") ~= nil,
    "unlock: the mover shows, and it says how to move it")
SlashCmdList.GROGUE("  LOCK ")
check(db.locked == true and not f.mover:IsShown() and last():find("locked%.$") ~= nil, "lock, in any case and with spaces")
SlashCmdList.GROGUE("config")
check(panel:IsShown(), "config opens the panel")
SlashCmdList.GROGUE("config")
check(not panel:IsShown(), "and closes it")
ns:Set("scale", 2)
SlashCmdList.GROGUE("reset")
check(db.scale == 1 and last():find("settings reset to defaults") ~= nil, "reset")
SlashCmdList.GROGUE("bogus")
check(last():find("/grogue %[config | unlock | lock | reset%]") ~= nil, "anything else: the usage")
noErrors("no errors in /grogue")

------------------------------------------------------------------------------ drag errors
-- An error in a script on our own frames goes to the client's error frame, which is off by
-- default, so the drag handlers print theirs like every other handler (GR-L5).
print("== an error while dragging")
local function contained(fn, frame, message)
    H.failNext(fn == frame._OnDragStart and "StartMoving" or "StopMovingOrSizing", message)
    local ok = pcall(fn, frame, "LeftButton")
    return ok and said(message)
end
SlashCmdList.GROGUE("unlock")
check(contained(f._OnDragStart, f, "bar drag refused"), "an error starting the bar's drag is printed, not thrown")
check(contained(f._OnDragStop, f, "bar drop refused"), "an error dropping it is printed, not thrown")
SlashCmdList.GROGUE("lock")
SlashCmdList.GROGUE("config")
check(contained(panel._OnDragStart, panel, "panel drag refused"), "an error starting the panel's drag is printed, not thrown")
check(contained(panel._OnDragStop, panel, "panel drop refused"), "an error dropping it is printed, not thrown")
SlashCmdList.GROGUE("config")
newErrors()   -- the four above

------------------------------------------------------------------------------ the compartment
print("== the addon compartment")
local declared = {}
for line in io.lines(ADDON_DIR .. "/gRogue.toc") do
    local key, fn = line:gsub("\r$", ""):match("^##%s*(AddonCompartmentFunc%w*):%s*(%S+)")
    if key then
        declared[key] = fn
    end
end
local found = 0
for _, key in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
    if declared[key] and type(_G[declared[key]]) == "function" then
        found = found + 1
    end
end
check(found == 3, "the TOC's three compartment functions exist")
if found == 3 then
    local entry = H.loose("menuButton")
    _G[declared.AddonCompartmentFuncOnEnter]("gRogue", entry)
    check(GameTooltip._owner == entry and GameTooltip._anchor == "ANCHOR_LEFT" and GameTooltip:IsShown()
        and GameTooltip._lines[1] == "gRogue" and GameTooltip._lines[2] == "Click for settings",
        "hovering the entry: a tooltip beside it says a click opens the settings")
    _G[declared.AddonCompartmentFuncOnLeave]("gRogue", entry)
    check(not GameTooltip:IsShown(), "leaving it hides the tooltip")
    _G[declared.AddonCompartmentFunc]("gRogue", "LeftButton")
    check(panel:IsShown(), "a click opens the settings")
    _G[declared.AddonCompartmentFunc]("gRogue", "LeftButton")
    check(not panel:IsShown(), "another closes them")
end
noErrors("no errors in the compartment")

------------------------------------------------------------------------------ a reload in combat
print("== a reload in combat")
inCombat = true
gRogueDB = { hideOutOfCombat = true }
ns = session()
f = ns.frame
H.fire("PLAYER_ENTERING_WORLD")
check(f:IsShown(), "in combat from the first frame: shown, though hidden out of combat")
H.fire("PLAYER_REGEN_ENABLED")
check(not f:IsShown(), "combat over: hidden")
inCombat = false
noErrors("no errors reloading in combat")

------------------------------------------------------------------------------ vehicles
-- In a vehicle the player's own combo points don't apply, so the bar hides (GR-L4).
print("== a reload in a vehicle")
inVehicle = true
gRogueDB = nil
ns = session()
f = ns.frame
H.fire("PLAYER_ENTERING_WORLD")
check(not f:IsShown(), "in a vehicle from the first frame: hidden")
inVehicle = false
H.fire("UNIT_EXITED_VEHICLE", "player")
check(f:IsShown(), "out of it: shown")
inVehicle = true
H.fire("UNIT_ENTERED_VEHICLE", "player")
check(not f:IsShown(), "into one again: hidden")
inVehicle = false
H.fire("PLAYER_ENTERING_WORLD")
check(f:IsShown(), "a loading screen that ends the ride shows it, even without UNIT_EXITED_VEHICLE")
noErrors("no errors reloading in a vehicle")

print("== a client without the vehicle events")
missingEvents.UNIT_ENTERED_VEHICLE, missingEvents.UNIT_EXITED_VEHICLE = true, true
ns = session()
f = ns.frame
H.fire("PLAYER_ENTERING_WORLD")
check(said("could not register UNIT_ENTERED_VEHICLE") and said("could not register UNIT_EXITED_VEHICLE"),
    "it says it can't follow vehicles")
comboPoints = 3
H.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
check(f:IsShown() and allBars(pipsOf(f), 3), "and the bar works without them")
newErrors()   -- the two lines above
missingEvents.UNIT_ENTERED_VEHICLE, missingEvents.UNIT_EXITED_VEHICLE = nil, nil
comboPoints = 0

------------------------------------------------------------------------------ a broken save
-- A saved value of the wrong type, past its slider's range, off its list, or a colour
-- without numeric r, g and b goes back to its default at load, so one bad value can't
-- break every layout refresh (GR-M2).
print("== a save with values this version can't use")
local NAN, INF = 0 / 0, 1 / 0
gRogueDB = {
    point = "MIDDLE", relativePoint = 3, x = INF, y = "low", locked = "no",
    orientation = "DIAGONAL", reverse = 1, pipWidth = "wide", pipHeight = 500, spacing = -1,
    scale = 0, alpha = NAN, texture = 7, smooth = "yes",
    fillColor = { r = "red", g = 0, b = 0 }, emptyColor = true, emptyAlpha = 2,
    border = {}, borderSize = 0.5, borderColor = { r = 2, g = 0, b = 0 },
    usePipColors = "no", hideWithoutTarget = 0, hideOutOfCombat = "false",
    pipColors = { { r = 0.1, g = 0.2, b = 0.3 }, true, { r = "x" }, "x", { r = 0, g = 0, b = NAN } },
    bogus = 7,
}
ns = session()
db = ns.db
local back, keys = {}, {}
for key, default in pairs(ns.defaults) do
    keys[#keys + 1] = key
    if key ~= "pipColors" and not same(db[key], default) then
        back[#back + 1] = key
    end
end
table.sort(keys)
check(#back == 0, "every setting is back to its default" .. (#back > 0 and (", but not " .. table.concat(back, ", ")) or ""))
local defaultPips = ns.defaults.pipColors
check(same(db.pipColors[1], { r = 0.1, g = 0.2, b = 0.3 }) and same(db.pipColors[2], defaultPips[2])
    and same(db.pipColors[3], defaultPips[3]) and same(db.pipColors[4], defaultPips[4])
    and same(db.pipColors[5], defaultPips[5]), "each point's colour is checked on its own: the good one kept")
check(db.bogus == 7, "a key this version does not know is left alone")
check(said("reset saved settings this version can't use: " .. table.concat(keys, ", ") .. "%.$"), "and it says which")
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors laying out the bar")
f = ns.frame
at = f and f._points and f._points.CENTER
check(at ~= nil and at.x == 0 and at.y == -180 and f._scale == 1 and f._width == 166 and f._height == 12,
    "the bar is drawn as by default")

print("== a save at the ends of every range")
local ends = copy(ns.defaults)
ends.point, ends.relativePoint, ends.x, ends.y = "BOTTOMRIGHT", "TOPLEFT", -1234.5, 0
ends.pipWidth, ends.pipHeight, ends.spacing, ends.scale = 4, 100, 0, 0.5
ends.alpha, ends.emptyAlpha, ends.borderSize, ends.locked = 0.1, 0, 6, false
ends.orientation, ends.texture, ends.fillColor = "VERTICAL", "raid", { r = 0, g = 1, b = 0 }
gRogueDB = copy(ends)
ns = session()
check(same(ns.db, ends) and not said("can't use"), "every value kept, nothing said")
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors laying out the bar")
at = ns.frame._points.BOTTOMRIGHT
check(at ~= nil and at.x == -2469 and at.relPoint == "TOPLEFT" and ns.frame._scale == 0.5, "drawn where it was saved")

print("== a save that is not a table")
gRogueDB = "corrupt"
ns = session()
check(type(gRogueDB) == "table" and ns.db == gRogueDB and same(gRogueDB, ns.defaults), "the defaults, in a new table")
check(ns.frame ~= nil and said("saved settings unreadable; using the defaults%."), "the bar is made, and it says so")
H.fire("PLAYER_ENTERING_WORLD")
noErrors("no errors")

------------------------------------------------------------------------------ no interpolation
-- SetValue's interpolation can't be nil, so a client without the enum, or without either
-- member, must get a bar that snaps with the count as SetValue's only argument, and no
-- smooth fill check, rather than an error at every update with smooth fill on (GR-M1).
local Interpolation = Enum.StatusBarInterpolation
local clients = {
    { "a client without StatusBarInterpolation", nil },
    { "a client without StatusBarInterpolation.ExponentialEaseOut", { Immediate = 0 } },
    { "a client without StatusBarInterpolation.Immediate", { ExponentialEaseOut = 1 } },
}
for _, client in ipairs(clients) do
    print("== " .. client[1])
    Enum.StatusBarInterpolation = client[2]
    gRogueDB = nil   -- smooth fill on, the default
    comboPoints = 0
    ns = session()
    check(ns.canSmooth == false, "no smooth fill on offer")
    H.fire("PLAYER_ENTERING_WORLD")
    comboPoints = "secret"
    H.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
    local bare = pipsOf(ns.frame)
    check(allBars(bare, "secret") and modes(bare, nil, nil), "the count reaches every bar, as SetValue's only argument")
    noErrors("no errors at an update")
    SlashCmdList.GROGUE("config")
    check(gRogueOptions:IsShown() and control("Smooth fill") == nil, "the panel opens, without the smooth fill check")
    noErrors("no errors in the panel")
end
Enum.StatusBarInterpolation = Interpolation
comboPoints = 0

------------------------------------------------------------------------------ no GetComboPoints
-- A build without GetComboPoints reads the player's combo point power instead, which lags
-- a target change, rather than raising at every update (GR-L1).
print("== a client without GetComboPoints")
local GetComboPointsStub = GetComboPoints
GetComboPoints = nil
gRogueDB = nil
ns = session()
H.fire("PLAYER_ENTERING_WORLD")
local fallback = pipsOf(ns.frame)
comboPoints = "secret"
H.fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
check(allBars(fallback, "secret") and H.calls.UnitPower > 0, "the count comes from UnitPower's combo points, a secret too")
comboPoints = 2
H.fire("PLAYER_TARGET_CHANGED")
check(allBars(fallback, 2), "a plain count too")
noErrors("no errors at an update")
check(#H.leaks == 0 and #H.readBacks == 0, "the secret went to SetValue and nowhere else")
GetComboPoints = GetComboPointsStub
comboPoints = 0

check((looseRefusedFonts or 0) == 0, "no font string asked SetFont for an addon's file, which the client refuses")

print(("%d passed, %d failed"):format(passes, failures))
os.exit(failures == 0 and 0 or 1)
