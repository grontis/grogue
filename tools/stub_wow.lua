-- tools/stub_wow.lua -- just enough of the WoW client to load gRogue and drive it.
--
-- Every frame is loose: a capitalised method not modelled here is a no-op, and the ones
-- the smoke reads back record what they were given. A few are as strict as the client: an
-- anchor point it does not know, a scale that is not above 0 and a colour channel that is
-- not a number are errors. gRogue touches no Blizzard frame but ColorPickerFrame and
-- GameTooltip, which are loose too.
--
-- Secrets are sentinel tables that throw on comparison, arithmetic, concatenation and
-- indexing, like the client's. Lua cannot make one throw on == against a number or in a
-- truth test, so the stub also records any method but SetValue that is handed one, and any
-- read of a bar's value while it holds one: the count may reach StatusBar:SetValue and
-- nothing else.
--
-- The client is set through globals the smoke flips: playerClass, targetExists, inCombat,
-- comboPoints (a number, or "secret" for a new secret on every read), GetComboPoints and
-- Enum. gRogueDB is the SavedVariables the next session loads.
--
-- Loaded by tools/smoke.lua with the addon's directory; returns a handle that loads the
-- addon as a new session, fires events and reaches the records.

local ADDON_DIR = ...

----------------------------------------------------------------------------------
-- secrets
----------------------------------------------------------------------------------

local function refuse(what)
    return function()
        error("attempt to " .. what .. " a secret value", 2)
    end
end

local SECRET_MT = {
    __index = refuse("index"),
    __newindex = refuse("index"),
    __call = refuse("call"),
    __eq = refuse("compare"),
    __lt = refuse("compare"),
    __le = refuse("compare"),
    __concat = refuse("concatenate"),
    __add = refuse("perform arithmetic on"),
    __sub = refuse("perform arithmetic on"),
    __mul = refuse("perform arithmetic on"),
    __div = refuse("perform arithmetic on"),
    __mod = refuse("perform arithmetic on"),
    __pow = refuse("perform arithmetic on"),
    __unm = refuse("perform arithmetic on"),
}

local secrets = setmetatable({}, { __mode = "k" })

local function mksecret()
    local s = setmetatable({}, SECRET_MT)
    secrets[s] = true
    return s
end

function issecretvalue(v)
    return type(v) == "table" and secrets[v] == true
end

----------------------------------------------------------------------------------
-- frames
----------------------------------------------------------------------------------

local leaks = {}       -- methods other than SetValue that were handed a secret
local readBacks = {}   -- reads of a bar's value while it held a secret

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local Loose = {}
local loose

-- Textures and font strings, kept on their parent so the smoke can find a control by
-- its label.
local function region(parent, kind, name, layer)
    local r = loose(name)
    r._type, r._parent, r._layer = kind, parent, layer
    parent._regions = parent._regions or {}
    parent._regions[#parent._regions + 1] = r
    return r
end

function Loose:GetName() return self._name end
function Loose:GetParent() return self._parent end
function Loose:CreateTexture(name, layer) return region(self, "Texture", name, layer) end
function Loose:CreateFontString(name, layer) return region(self, "FontString", name, layer) end

function Loose:SetWidth(w) self._width = w end
function Loose:GetWidth() return self._width or 0 end
function Loose:SetHeight(h) self._height = h end
function Loose:GetHeight() return self._height or 0 end
function Loose:SetSize(w, h) self._width, self._height = w, h end
function Loose:GetSize() return self._width or 0, self._height or 0 end

function Loose:SetPoint(point, rel, relPoint, x, y)
    if type(rel) == "number" then
        rel, relPoint, x, y = nil, nil, rel, relPoint
    end
    if not ANCHORS[point] or (relPoint ~= nil and not ANCHORS[relPoint]) then
        error(("SetPoint(): unknown anchor point (%s, %s)"):format(tostring(point), tostring(relPoint)), 2)
    end
    self._points = self._points or {}
    self._points[point] = { rel = rel or self._parent, relPoint = relPoint or point, x = x or 0, y = y or 0 }
end

-- After a drag the client answers where the frame was dropped: the smoke sets _dragTo.
function Loose:GetPoint()
    if self._dragTo then
        return unpack(self._dragTo)
    end
    for point, p in pairs(self._points or {}) do
        return point, p.rel, p.relPoint, p.x, p.y
    end
end

function Loose:ClearAllPoints() self._points = {}; self._allPoints = nil end
function Loose:SetAllPoints(rel) self._points = {}; self._allPoints = rel or self._parent end

function Loose:Show()
    local was = self._shown
    self._shown = true
    if not was and self._OnShow then self._OnShow(self) end
end
function Loose:Hide()
    local was = self._shown
    self._shown = false
    if was and self._OnHide then self._OnHide(self) end
end
function Loose:IsShown() return self._shown == true end
function Loose:SetShown(shown) if shown then self:Show() else self:Hide() end end

function Loose:SetScale(scale)
    if type(scale) ~= "number" or not (scale > 0) then
        error("SetScale(): the scale must be above 0, not " .. tostring(scale), 2)
    end
    self._scale = scale
end
function Loose:SetAlpha(alpha) self._alpha = alpha end

local function channels(method, r, g, b, a)
    local given = { r, g, b, a }
    for i = 1, 4 do
        local v = given[i]
        if not (type(v) == "number" or issecretvalue(v) or (i == 4 and v == nil)) then
            error(("%s(): bad argument #%d (number expected, got %s)"):format(method, i, type(v)), 3)
        end
    end
end
function Loose:SetColorTexture(r, g, b, a) channels("SetColorTexture", r, g, b, a); self._color = { r, g, b, a or 1 } end
function Loose:SetStatusBarColor(r, g, b, a) channels("SetStatusBarColor", r, g, b, a); self._barColor = { r, g, b, a } end
function Loose:SetTextColor(r, g, b, a) channels("SetTextColor", r, g, b, a); self._textColor = { r, g, b, a } end

function Loose:SetText(text) self._text = text end
function Loose:GetText() return self._text end
function Loose:SetFont(path, size, flags) self._font = { path, size, flags } end

function Loose:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
-- StatusBar:SetValue(value, interpolation): the interpolation is a StatusBarInterpolation,
-- Nilable = false with a default of Immediate (Forever's SimpleStatusBarAPIDocumentation).
-- A call may leave it out. Whether the client takes an explicit nil as the default is
-- unmeasured, so the stub refuses one, the stricter reading.
function Loose:SetValue(...)
    local value, interpolation = ...
    local count = select("#", ...)
    if self._type == "StatusBar" and count >= 2 and type(interpolation) ~= "number" then
        error("SetValue(): bad argument #2 (StatusBarInterpolation expected, got " .. type(interpolation) .. ")", 2)
    end
    self._value, self._interp, self._args = value, interpolation, count
    self._secret = issecretvalue(value) or nil
    if self._OnValueChanged then self._OnValueChanged(self, value) end
end
function Loose:GetValue()
    if self._secret then readBacks[#readBacks + 1] = "GetValue" end
    return self._value
end
-- No secret restriction in the client: the clip frame anchors to it.
function Loose:GetStatusBarTexture()
    if not self._fill then
        self._fill = region(self, "Texture")
    end
    return self._fill
end
function Loose:SetStatusBarTexture(path) self:GetStatusBarTexture()._texture = path end
function Loose:SetOrientation(orientation) self._orientation = orientation end
function Loose:SetReverseFill(reverse) self._reverse = reverse end
function Loose:SetClipsChildren(clips) self._clips = clips end

function Loose:EnableMouse(on) self._mouse = on and true or false end
function Loose:SetMovable(movable) self._movable = movable end
function Loose:StartMoving() self._moving = true end
function Loose:StopMovingOrSizing() self._moving = false end

function Loose:SetScript(handler, fn) self["_" .. handler] = fn end
function Loose:GetScript(handler) return self["_" .. handler] end
function Loose:Click(button) if self._OnClick then self._OnClick(self, button or "LeftButton") end end

function Loose:RegisterEvent(event)
    self._events = self._events or {}
    self._events[event] = true
end
-- A unit event reaches the frame only for the units it names, as in the client.
function Loose:RegisterUnitEvent(event, ...)
    self._events = self._events or {}
    self._events[event] = { ... }
end
function Loose:UnregisterEvent(event)
    if self._events then self._events[event] = nil end
end

-- Every method call goes through here, so the stub sees each argument handed to the client.
local LOOSE_MT = {
    __index = function(_, key)
        local method = Loose[key]
        if not method then
            if type(key) ~= "string" or not key:match("^%u") then
                return nil
            end
            method = function() end
        end
        return function(self, ...)
            if key ~= "SetValue" then
                for i = 1, select("#", ...) do
                    if issecretvalue((select(i, ...))) then
                        leaks[#leaks + 1] = key
                        break
                    end
                end
            end
            return method(self, ...)
        end
    end,
}

loose = function(name)
    return setmetatable({ _name = name }, LOOSE_MT)
end

local created = {}   -- every frame made this session, in order
local named = {}     -- the globals CreateFrame set this session

function CreateFrame(frameType, name, parent, template)
    local f = loose(name)
    f._type, f._parent, f._template = frameType, parent, template
    created[#created + 1] = f
    if name then
        _G[name] = f
        named[#named + 1] = name
    end
    return f
end

----------------------------------------------------------------------------------
-- the client
----------------------------------------------------------------------------------

SlashCmdList = {}
UISpecialFrames = {}
UIParent = loose("UIParent")
STANDARD_TEXT_FONT = [[Fonts\FRIZQT__.TTF]]

Enum = {
    StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 },
}

strupper, strlower = string.upper, string.lower
tinsert = table.insert

function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

function strtrim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function strjoin(sep, ...)
    return table.concat({ ... }, sep)
end

function tostringall(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[i] = tostring((select(i, ...)))
    end
    return unpack(out, 1, select("#", ...))
end

playerClass = "ROGUE"
function UnitClass(unit)
    return playerClass:sub(1, 1) .. playerClass:sub(2):lower(), playerClass
end

targetExists = false
function UnitExists(unit)
    return unit == "target" and targetExists
end

inCombat = false
function InCombatLockdown()
    return inCombat
end

-- The count on the target: a number, or "secret".
comboPoints = 0
function GetComboPoints(unit, target)
    if type(unit) ~= "string" or type(target) ~= "string" then
        error("GetComboPoints(): needs a unit and a target", 2)
    end
    if comboPoints == "secret" then
        return mksecret()
    end
    return comboPoints
end

----------------------------------------------------------------------------------
-- chat and Blizzard's frames
----------------------------------------------------------------------------------

local printed = {}

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    printed[#printed + 1] = table.concat(parts, " ")
    if os.getenv("SMOKE_VERBOSE") then
        io.write("  | ", printed[#printed], "\n")
    end
end

GameTooltip = loose("GameTooltip")
function GameTooltip:SetOwner(owner, anchor) self._owner, self._anchor = owner, anchor end
function GameTooltip:SetText(text) self._lines = { text } end
function GameTooltip:AddLine(text) self._lines[#self._lines + 1] = text end

-- Opened by SetupColorPickerAndShow; Hide() closes it without running cancelFunc. The
-- smoke plays the user: it sets r, g, b and calls info.swatchFunc or info.cancelFunc.
ColorPickerFrame = loose("ColorPickerFrame")
function ColorPickerFrame:SetupColorPickerAndShow(info)
    self.info = info
    self.r, self.g, self.b = info.r, info.g, info.b
    self:Show()
end
function ColorPickerFrame:GetColorRGB() return self.r, self.g, self.b end
function ColorPickerFrame:GetPreviousValues() return self.info.r, self.info.g, self.info.b end

----------------------------------------------------------------------------------
-- sessions and events
----------------------------------------------------------------------------------

-- A new session: the last one's frames, globals, chat and records are gone, and the TOC's
-- files run in order into a fresh ns, as the client loads them. ADDON_LOADED is the
-- smoke's to fire, once it has set gRogueDB.
local function load()
    for i = #created, 1, -1 do
        created[i] = nil
    end
    for i = #named, 1, -1 do
        _G[named[i]] = nil
        named[i] = nil
    end
    wipe(printed)
    wipe(leaks)
    wipe(readBacks)
    wipe(SlashCmdList)
    wipe(UISpecialFrames)
    ColorPickerFrame.info, ColorPickerFrame._shown = nil, false
    GameTooltip._owner, GameTooltip._lines, GameTooltip._shown = nil, nil, false

    local ns = {}
    for line in io.lines(ADDON_DIR .. "/gRogue.toc") do
        line = line:gsub("\r$", "")
        if not line:match("^%s*#") and line:match("%S") then
            assert(loadfile(ADDON_DIR .. "/" .. line))("gRogue", ns)
        end
    end
    return ns
end

local function wants(units, unit)
    if units == true then
        return true
    end
    for _, u in ipairs(units) do
        if u == unit then
            return true
        end
    end
    return false
end

local function fire(event, ...)
    for _, f in ipairs(created) do
        local units = f._events and f._events[event]
        if units and f._OnEvent and wants(units, (...)) then
            f._OnEvent(f, event, ...)
        end
    end
end

return {
    load = load,
    fire = fire,
    created = created,
    printed = printed,
    leaks = leaks,
    readBacks = readBacks,
    loose = loose,
    secret = mksecret,
}
