-- UI/Options.lua -- the settings window.
--
-- A standalone window rather than a page in Blizzard's settings, because this client has
-- no Settings API (see UI/Widgets.lua). Opened by /grogue and from the addon compartment;
-- Escape closes it. Every change applies immediately.

local addonName, ns = ...

local Widgets = ns.Widgets
local T = Widgets.theme

local Options = {}
ns.Options = Options

local panel
local controls = {}

local PAD = 14
local COLUMN = 230
local GUTTER = 24
local WIDTH = PAD * 2 + COLUMN * 2 + GUTTER

local ORIENTATION_NAMES = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }

local TEXTURE_NAMES = {}
for key, texture in pairs(ns.textures) do
    TEXTURE_NAMES[key] = texture.label
end

local function percent(v)
    return ("%d%%"):format(math.floor(v + 0.5))
end

----------------------------------------------------------------------------------
-- building
----------------------------------------------------------------------------------

local function column(x)
    local y = -(PAD + 26)
    local api = {}
    function api.place(frame, gap)
        frame:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
        frame:SetWidth(COLUMN)
        y = y - frame:GetHeight() - (gap or 6)
        return frame
    end
    function api.bottom() return y end
    return api
end

local function check(col, key, label)
    local control = col.place(Widgets.Check(panel, {
        label = label,
        onChange = function(on) ns:Set(key, on) end,
    }))
    control.kind = "check"
    controls[key] = control
end

-- A slider runs from end to end of its setting's limits (ns.limits), which a saved value is
-- held to as well. A percent slider shows 0-100 and stores 0-1.
local function slider(col, key, label, step, isPercent)
    local limits, unit = ns.limits[key], isPercent and 100 or 1
    local control = col.place(Widgets.Slider(panel, {
        label = label, step = step,
        min = math.floor(limits[1] * unit + 0.5), max = math.floor(limits[2] * unit + 0.5),
        format = isPercent and percent or nil,
        onChange = function(v) ns:Set(key, isPercent and v / 100 or v) end,
    }))
    control.kind = "slider"
    control.isPercent = isPercent
    controls[key] = control
end

local function dropdown(col, key, label, options, names)
    local control = col.place(Widgets.Dropdown(panel, {
        label = label,
        width = 120,
        options = options,
        names = names,
        onChange = function(v) ns:Set(key, v) end,
    }))
    control.kind = "dropdown"
    controls[key] = control
end

-- getColor runs at use time because a reset replaces the colour tables.
local function swatch(col, name, label, getColor)
    local control = col.place(Widgets.Swatch(panel, {
        label = label,
        onChange = function(r, g, b)
            local color = getColor()
            color.r, color.g, color.b = r, g, b
            ns:Refresh()
        end,
    }), 2)
    control.kind = "swatch"
    control.getColor = getColor
    controls[name] = control
end

local function build()
    local db = ns.db

    panel = CreateFrame("Frame", "gRogueOptions", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:Hide()

    Widgets.Backdrop(panel, T.backdrop, T.border, 0.97)

    local header = panel:CreateTexture(nil, "BORDER")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    header:SetHeight(24)
    Widgets.Fill(header, T.header)

    local title = Widgets.Label(panel, "gRogue", T.size.title, T.accent)
    title:SetPoint("LEFT", panel, "TOPLEFT", PAD, -13)
    local subtitle = Widgets.Label(panel, "combo points", T.size.small, T.muted)
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local close = Widgets.Button(panel, "x", function() Options.Hide() end, 22)
    close:SetPoint("RIGHT", panel, "TOPRIGHT", -6, -13)

    local left = column(PAD)
    local right = column(PAD + COLUMN + GUTTER)

    left.place(Widgets.Heading(panel, "Position"))
    check(left, "locked", "Lock position")

    left.place(Widgets.Heading(panel, "Layout"), 6)
    dropdown(left, "orientation", "Orientation", ns.choices.orientation, ORIENTATION_NAMES)
    check(left, "reverse", "Reverse direction")
    slider(left, "pipWidth", "Point width", 1)
    slider(left, "pipHeight", "Point height", 1)
    slider(left, "spacing", "Spacing", 1)
    slider(left, "scale", "Scale", 5, true)
    slider(left, "alpha", "Opacity", 5, true)

    left.place(Widgets.Heading(panel, "Visibility"), 6)
    check(left, "hideWithoutTarget", "Hide without a target")
    check(left, "hideOutOfCombat", "Hide out of combat")

    right.place(Widgets.Heading(panel, "Style"))
    dropdown(right, "texture", "Texture", ns.choices.texture, TEXTURE_NAMES)
    if ns.canSmooth then
        check(right, "smooth", "Smooth fill")
    end
    swatch(right, "fillColor", "Filled colour", function() return db.fillColor end)
    swatch(right, "emptyColor", "Empty colour", function() return db.emptyColor end)
    slider(right, "emptyAlpha", "Empty opacity", 5, true)
    check(right, "border", "Show border")
    slider(right, "borderSize", "Border size", 1)
    swatch(right, "borderColor", "Border colour", function() return db.borderColor end)

    right.place(Widgets.Heading(panel, "Point colours"), 6)
    check(right, "usePipColors", "Colour each point separately")
    for i = 1, ns.MAX_POINTS do
        swatch(right, "pipColor" .. i, "Point " .. i, function() return db.pipColors[i] end)
    end

    local bottom = math.min(left.bottom(), right.bottom()) - 10

    local hint = Widgets.Label(panel, "Unlock to drag the bar. Changes apply immediately.",
        T.size.small, T.muted)
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, bottom - 6)

    local reset = Widgets.Button(panel, "Reset all", function() ns:ResetSettings() end, 90)
    reset:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, bottom)

    panel:SetSize(WIDTH, -bottom + 22 + PAD)

    if type(_G.UISpecialFrames) == "table" then
        tinsert(_G.UISpecialFrames, "gRogueOptions")
    end
end

----------------------------------------------------------------------------------
-- state
----------------------------------------------------------------------------------

-- Controls' setters are quiet, so filling the panel writes nothing back.
function Options.Refresh()
    if not panel then
        return
    end
    local db = ns.db
    for key, control in pairs(controls) do
        if control.kind == "check" then
            control:SetChecked(db[key])
        elseif control.kind == "slider" then
            control:SetValue(control.isPercent and math.floor(db[key] * 100 + 0.5) or db[key])
        elseif control.kind == "dropdown" then
            control:SetValue(db[key])
        elseif control.kind == "swatch" then
            local color = control.getColor()
            control:SetColor(color.r, color.g, color.b)
        end
    end
end

function Options.Show()
    if not panel then
        build()
    end
    Options.Refresh()
    panel:Show()
end

function Options.Hide()
    if panel then
        panel:Hide()
    end
end

function Options.Toggle()
    if panel and panel:IsShown() then
        Options.Hide()
    else
        Options.Show()
    end
end
