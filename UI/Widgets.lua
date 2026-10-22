-- UI/Widgets.lua -- the controls the settings panel is made of.
--
-- Copied from gFrames' UI/Widgets.lua as it was on 2026-10-03 (itself adapted from
-- gThreat's), so the g-addons share one look; how each control behaves is gFrames'
-- docs/ui.md. Only the accent and the font lookup differ. The two are not linked:
-- gFrames' copy has moved on since, and a fix to one is a fix to that one only.
--
-- Built from core widget types (Frame, Button, Slider) and plain textures, with no
-- Blizzard template: Blizzard's options templates register with its settings manager in
-- their OnLoad, and the failure mode is an entry in Blizzard's tree or a taint path
-- between our settings and their panel. The one Blizzard piece is ColorPickerFrame behind
-- the colour swatch.

local addonName, ns = ...

local FONT = STANDARD_TEXT_FONT

local Widgets = {}
ns.Widgets = Widgets

local ROW = 20            -- height of a check, dropdown, swatch or button row
local SLIDER_ROW = 30     -- label above, slider below

Widgets.theme = {
    backdrop = { 0.06, 0.06, 0.07 },
    header   = { 0.10, 0.10, 0.12 },
    border   = { 0.24, 0.24, 0.27 },
    track    = { 0.12, 0.12, 0.14 },   -- inside a control: box, field, button, slider track
    hover    = { 0.17, 0.17, 0.20 },   -- a list row under the pointer
    accent   = { 1.00, 0.96, 0.41 },   -- rogue class yellow, as in gRogue: in chat
    text     = { 0.92, 0.92, 0.92 },
    soft     = { 0.70, 0.70, 0.72 },
    muted    = { 0.50, 0.50, 0.53 },
    size     = { title = 14, label = 12, small = 10 },
}
local T = Widgets.theme

----------------------------------------------------------------------------------
-- plumbing
----------------------------------------------------------------------------------

local function fill(texture, color, alpha)
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
end
Widgets.Fill = fill

local function paint(textures, color)
    for _, texture in ipairs(textures) do
        fill(texture, color)
    end
end

-- Four 1px edges and a background, no BackdropTemplate. Returns the background and the
-- edges, which a control recolours to show hover and focus.
function Widgets.Backdrop(frame, background, border, alpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    fill(bg, background, alpha)

    local edges = {}
    for _, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
    }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetPoint(spec[1], frame, spec[1], 0, 0)
        edge:SetPoint(spec[2], frame, spec[2], 0, 0)
        if spec[3] then edge:SetHeight(1) else edge:SetWidth(1) end
        fill(edge, border)
        edges[#edges + 1] = edge
    end
    return bg, edges
end

-- Every clickable control says so the same way: its outline takes the accent while the
-- pointer is over it. `held()` keeps the accent after the pointer leaves (an open list).
local function Hover(button, outline, held)
    button:SetScript("OnEnter", function()
        paint(outline, T.accent)
    end)
    button:SetScript("OnLeave", function()
        if not (held and held()) then
            paint(outline, T.border)
        end
    end)
end

function Widgets.Label(parent, text, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetFont(FONT, size or T.size.label, "")
    local c = color or T.text
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH(justify or "LEFT")
    if type(fs.SetWordWrap) == "function" then fs:SetWordWrap(false) end
    fs:SetText(text or "")
    return fs
end

-- A section heading: muted capitals with a divider under it.
function Widgets.Heading(parent, text)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    local fs = Widgets.Label(row, strupper(text), T.size.small, T.muted)
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    line:SetHeight(1)
    fill(line, T.border)
    return row
end

----------------------------------------------------------------------------------
-- a check box: on or off
----------------------------------------------------------------------------------

function Widgets.Check(parent, spec)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)

    local box = row:CreateTexture(nil, "BORDER")
    box:SetSize(12, 12)
    box:SetPoint("LEFT", row, "LEFT", 0, 0)
    fill(box, T.border)

    local inner = row:CreateTexture(nil, "ARTWORK")
    inner:SetSize(10, 10)
    inner:SetPoint("CENTER", box, "CENTER", 0, 0)
    fill(inner, T.track)

    local tick = row:CreateTexture(nil, "OVERLAY")
    tick:SetSize(6, 6)
    tick:SetPoint("CENTER", box, "CENTER", 0, 0)
    fill(tick, T.accent)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    row.checked = false

    function row:SetChecked(on)
        row.checked = on and true or false
        if row.checked then tick:Show() else tick:Hide() end
    end

    Hover(row, { box })

    -- Every control's callback is guarded: an error must not escape into a click.
    row:SetScript("OnClick", ns.Guard(function()
        row:SetChecked(not row.checked)
        if spec.onChange then spec.onChange(row.checked) end
    end))

    return row
end

----------------------------------------------------------------------------------
-- a dropdown: one of a list
--
-- A field showing the current choice, with a chevron. A click opens the list under it,
-- the current choice marked in the accent. A click on a row chooses it and closes the
-- list; a click anywhere else closes it unchanged, through a screen-sized catcher under
-- the list. One list is open at a time. The list belongs to the dropdown, so it closes
-- with the panel, and reopening the panel never finds it still open.
----------------------------------------------------------------------------------

local openDropdown   -- the dropdown whose list is showing

-- A down-pointing triangle from four 1px rows, so it takes the theme's colour without an
-- art file.
local function Chevron(parent)
    local chevron = CreateFrame("Frame", nil, parent)
    chevron:SetSize(7, 4)
    for i, width in ipairs({ 7, 5, 3, 1 }) do
        local row = chevron:CreateTexture(nil, "OVERLAY")
        row:SetSize(width, 1)
        row:SetPoint("TOP", chevron, "TOP", 0, 1 - i)
        fill(row, T.soft)
    end
    return chevron
end

function Widgets.Dropdown(parent, spec)
    local width = spec.width or 130

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW + 2)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)

    local field = CreateFrame("Button", nil, row)
    field:SetSize(width, ROW)
    field:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    local _, fieldEdges = Widgets.Backdrop(field, T.track, T.border)
    row.field = field

    local text = Widgets.Label(field, "")
    text:SetPoint("LEFT", field, "LEFT", 6, 0)
    text:SetPoint("RIGHT", field, "RIGHT", -18, 0)
    row.text = text

    Chevron(field):SetPoint("RIGHT", field, "RIGHT", -6, 0)

    local list = CreateFrame("Frame", nil, row)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetSize(width, #spec.options * ROW + 2)
    list:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -2)
    list:EnableMouse(true)
    Widgets.Backdrop(list, T.backdrop, T.border)
    list:Hide()
    row.list = list

    local catcher = CreateFrame("Button", nil, row)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:SetAllPoints(UIParent)
    catcher:RegisterForClicks("AnyUp")
    catcher:Hide()
    row.catcher = catcher

    local value
    local items = {}
    row.items = items

    local function name(option)
        return spec.names and spec.names[option] or tostring(option)
    end

    local function mark()
        for _, item in ipairs(items) do
            local current = item.option == value
            if current then item.mark:Show() else item.mark:Hide() end
            local c = current and T.accent or T.text
            item.text:SetTextColor(c[1], c[2], c[3])
        end
    end

    -- However the list goes away: a choice, a click outside, the panel closing.
    local closing = false
    local function close()
        if closing then
            return
        end
        closing = true
        list:Hide()
        catcher:Hide()
        for _, item in ipairs(items) do
            item.highlight:Hide()
        end
        paint(fieldEdges, T.border)
        if openDropdown == row then
            openDropdown = nil
        end
        closing = false
    end
    list:SetScript("OnHide", close)
    catcher:SetScript("OnClick", close)

    for i, option in ipairs(spec.options) do
        local item = CreateFrame("Button", nil, list)
        item:SetHeight(ROW)
        item:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (i - 1) * ROW)
        item:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -1 - (i - 1) * ROW)
        item.option = option

        item.highlight = item:CreateTexture(nil, "BACKGROUND")
        item.highlight:SetAllPoints(item)
        fill(item.highlight, T.hover)
        item.highlight:Hide()

        item.mark = item:CreateTexture(nil, "ARTWORK")
        item.mark:SetSize(2, ROW - 8)
        item.mark:SetPoint("LEFT", item, "LEFT", 3, 0)
        fill(item.mark, T.accent)

        item.text = Widgets.Label(item, name(option))
        item.text:SetPoint("LEFT", item, "LEFT", 10, 0)
        item.text:SetPoint("RIGHT", item, "RIGHT", -6, 0)

        item:SetScript("OnEnter", function() item.highlight:Show() end)
        item:SetScript("OnLeave", function() item.highlight:Hide() end)
        item:SetScript("OnClick", ns.Guard(function()
            close()
            if option ~= value then
                row:SetValue(option)
                if spec.onChange then spec.onChange(option) end
            end
        end))
        items[i] = item
    end

    -- Quiet, like every control's SetValue: filling the panel writes nothing back.
    function row:SetValue(option)
        value = option
        text:SetText(name(option))
        mark()
    end

    function row:Open()
        if openDropdown and openDropdown ~= row then
            openDropdown:Close()
        end
        openDropdown = row
        mark()
        catcher:Show()
        list:Show()
        paint(fieldEdges, T.accent)
    end

    row.Close = close

    function row:IsOpen()
        return list:IsShown()
    end

    Hover(field, fieldEdges, function() return list:IsShown() end)
    field:SetScript("OnClick", ns.Guard(function()
        if list:IsShown() then close() else row:Open() end
    end))

    return row
end

----------------------------------------------------------------------------------
-- a labelled slider: a number in a range
--
-- `format` turns the raw value into what the reader sees. SetValue is "quiet": the panel
-- filling itself in must not write every setting back to the value it already had.
----------------------------------------------------------------------------------

function Widgets.Slider(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SLIDER_ROW)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    local value = Widgets.Label(row, "", nil, T.soft, "RIGHT")
    value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    slider:SetHeight(12)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(spec.step or 1)
    if type(slider.SetObeyStepOnDrag) == "function" then
        pcall(slider.SetObeyStepOnDrag, slider, true)
    end
    slider:EnableMouse(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetHeight(4)
    fill(track, T.border)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 14)
    fill(thumb, T.accent)
    slider:SetThumbTexture(thumb)

    -- Snap to the step: a slider reports every pixel of a drag, not just the steps.
    local function snap(v)
        local step = spec.step or 1
        return math.floor((v - spec.min) / step + 0.5) * step + spec.min
    end

    local function show(v)
        value:SetText(spec.format and spec.format(v) or tostring(math.floor(v + 0.5)))
    end

    slider:SetScript("OnValueChanged", ns.Guard(function(_, v)
        if row.quiet then
            show(v)
            return
        end
        v = snap(v)
        show(v)
        if spec.onChange then spec.onChange(v) end
    end))

    function row:SetValue(v)
        row.quiet = true
        slider:SetValue(v)
        show(v)
        row.quiet = nil
    end

    row.slider = slider
    return row
end

----------------------------------------------------------------------------------
-- a colour swatch: a square of the colour and a label; a click opens the colour picker
----------------------------------------------------------------------------------

function Widgets.Swatch(parent, spec)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW)

    local frame = row:CreateTexture(nil, "BORDER")
    frame:SetSize(14, 14)
    frame:SetPoint("LEFT", row, "LEFT", 0, 0)
    fill(frame, T.border)

    local color = row:CreateTexture(nil, "ARTWORK")
    color:SetSize(12, 12)
    color:SetPoint("CENTER", frame, "CENTER", 0, 0)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local r, g, b = 1, 1, 1

    function row:SetColor(nr, ng, nb)
        r, g, b = nr, ng, nb
        color:SetColorTexture(r, g, b, 1)
    end

    local function set(nr, ng, nb)
        row:SetColor(nr, ng, nb)
        if spec.onChange then spec.onChange(nr, ng, nb) end
    end

    Hover(row, { frame })

    row:SetScript("OnClick", ns.Guard(function()
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
            ns.Print("the colour picker is not available on this client")
            return
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = ns.Guard(function()
                set(ColorPickerFrame:GetColorRGB())
            end),
            cancelFunc = ns.Guard(function()
                set(ColorPickerFrame:GetPreviousValues())
            end),
        })
    end))

    return row
end

----------------------------------------------------------------------------------
-- a button: an action, never a setting
--
-- A primary button is the one a dialog expects you to press: accent outline and label at
-- rest, and a lighter fill on hover. There is at most one per dialog.
----------------------------------------------------------------------------------

-- Dresses a Button in the theme without touching its OnClick, so it can dress a button
-- made from a template whose click handler must stay Blizzard's.
function Widgets.StyleButton(button, text, primary)
    local bg, edges = Widgets.Backdrop(button, T.track, primary and T.accent or T.border)

    local label = Widgets.Label(button, text, nil, primary and T.accent or T.text, "CENTER")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label = label

    if primary then
        button:SetScript("OnEnter", function() fill(bg, T.hover) end)
        button:SetScript("OnLeave", function() fill(bg, T.track) end)
    else
        Hover(button, edges)
    end
    -- Pressed: the label sinks a pixel.
    button:SetScript("OnMouseDown", function() label:SetPoint("CENTER", button, "CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function() label:SetPoint("CENTER", button, "CENTER", 0, 0) end)
    return button
end

function Widgets.Button(parent, text, onClick, width, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 90, ROW + 2)
    Widgets.StyleButton(button, text, primary)
    button:SetScript("OnClick", ns.Guard(onClick))
    return button
end
