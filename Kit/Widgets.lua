-- gkit Widgets.lua @ 3b70925: edit gkit, not this copy
-- Widgets.lua -- the controls a settings panel is made of, in one look.
--
-- Needs Kit/Init.lua and Kit/Theme.lua (Kit/Fonts.lua too when the panel font is an addon's file).
-- gFrames' UI/Widgets.lua, the superset of the lineage (gThreat's first, then gRogue's and gBars'),
-- with the font a parameter, the palette from the addon's tokens and the colour swatch in both
-- forms. How each control behaves is gFrames' docs/SPEC.md, UI design rules, Controls.
--
-- Reads from ns.kit:
--   tokens.panel   the palette (required; any token form Kit/Theme.lua reads): backdrop, header,
--                  border, track (inside a control), hover (a list row under the pointer),
--                  accent, text, soft, muted, and optionally warning; size = { title, label,
--                  small } (14, 12, 10)
--   widgets.font   the panel's font file (STANDARD_TEXT_FONT). A built-in face goes straight onto
--                  each string (CF-031); an addon's file goes through Kit/Fonts.lua's font
--                  objects, since a font string's own SetFont never takes one (CF-028)
--   config.colours "hex" or "rgb": the swatch's form when a control does not say (rgb)
--
-- Built from core widget types (Frame, Button, Slider, EditBox) and plain textures, with no
-- Blizzard template: Blizzard's options templates register with its settings manager in their
-- OnLoad, and the failure mode is an entry in Blizzard's tree or a taint path between the addon's
-- settings and their panel; its dropdown (DropdownButton and Menu) is template-driven and
-- unverified on this client (CF-120). The Blizzard pieces are ColorPickerFrame behind the swatch
-- and, in Kit/ReloadDialog.lua, the click handler of an InsecureActionButtonTemplate. Every
-- callback is guarded, so an error cannot escape into a click.
--
-- On ns.Widgets (and ns.Kit.Widgets):
--   theme                          the palette as { r, g, b } arrays, and size
--   Fill(texture, color [, alpha]), Backdrop(frame, background, border [, alpha]) -> bg, edges
--   Label(parent, text [, size, color, justify]), Heading(parent, text)
--   ShowTip(owner, text [, below]), HideTip(), TipFrame()
--   Check(parent, spec)       spec: label, tip, onChange(on); row:SetChecked(on); row.tick
--   Dropdown(parent, spec)    spec: label, tip, width, options, names, empty, onChange(option);
--                             row:SetValue, row:SetOptions(options [, names]), Open, Close, IsOpen
--   CloseDropdown(), ClearFocus()
--   Input(parent, spec)       spec: label, tip, width, maxLetters, onEnter(text); GetValue, SetValue
--   Tabs(parent, spec)        spec: pages, names, height, padding, onChange(page); bar:SetValue
--   Slider(parent, spec)      spec: label, tip, min, max, step, format, onChange(v); row:SetValue;
--                             row.slider, row.valueText
--   Swatch(parent, spec)      spec: label, tip, form ("hex" | "rgb"), get, onChange; row:SetColor
--                             (r, g, b), row:SetHex(hex)
--   StyleButton(button, text [, primary]), Button(parent, text, onClick [, width, primary]),
--   Press(button, label)      the label sinks a pixel while the button is held
--   ModeButton(parent, spec)  spec: start, stop, tip, tipBelow, onChange(on) -> on; SetOn,
--                             SetAvailable
--   Chevron(parent)
-- Every SetValue, SetChecked, SetOptions, SetColor and SetHex is quiet: filling a panel in writes
-- nothing back.

local addonName, ns = ...

local Kit = ns.Kit
if not (Kit and Kit.Init and Kit.Theme) then
    error("gkit: Kit/Init.lua and Kit/Theme.lua must load before Kit/Widgets.lua", 0)
end
local Init, Theme = Kit.Init, Kit.Theme
local Guard = Init.Guard

local ipairs, pairs, type = ipairs, pairs, type
local floor, ceil = math.floor, math.ceil

local Widgets = {}
Kit.Widgets = Widgets
ns.Widgets = Widgets

local ROW = 20            -- height of a check, dropdown, swatch or button row
local SLIDER_ROW = 30     -- label above, slider below

----------------------------------------------------------------------------------
-- the palette, from ns.kit.tokens.panel
----------------------------------------------------------------------------------

local REQUIRED = { "backdrop", "header", "border", "track", "hover", "accent", "text", "soft", "muted" }

local palette = type(ns.kit.tokens) == "table" and ns.kit.tokens.panel
if type(palette) ~= "table" then
    error("gkit Widgets: set ns.kit.tokens.panel, the settings panel's palette, where ns.kit is set", 0)
end

local T = { size = { title = 14, label = 12, small = 10 } }
if type(palette.size) == "table" then
    for k, v in pairs(palette.size) do
        T.size[k] = v
    end
end
for key, token in pairs(palette) do
    if key ~= "size" then
        local r, g, b = Theme.Color(token)
        if r == nil then
            error("gkit Widgets: ns.kit.tokens.panel." .. tostring(key) .. " is not a colour", 0)
        end
        T[key] = { r, g, b }
    end
end
for _, key in ipairs(REQUIRED) do
    if not T[key] then
        error("gkit Widgets: ns.kit.tokens.panel." .. key .. " is missing", 0)
    end
end
Widgets.theme = T

local cfg = ns.kit.widgets or {}

local function isAddonFile(file)
    return type(file) == "string" and file:lower():find("^interface[\\/]addons[\\/]") ~= nil
end

-- The panel font on a font string or an edit box, at size.
local function setFont(fs, size)
    local file = cfg.font or STANDARD_TEXT_FONT
    if isAddonFile(file) then
        if Kit.Fonts then
            Kit.Fonts.Apply(fs, file, size, "")
        end
        return
    end
    fs:SetFont(file, size, "")
end

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

-- Four 1px edges and a background, no BackdropTemplate. Returns the background and the edges,
-- which a control recolours to show hover and focus.
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

-- Every clickable control says so the same way: its outline takes the accent while the pointer is
-- over it. held() keeps the accent after the pointer leaves (an open list). tip: help shown beside
-- owner meanwhile, or under it (below). While live() says the control can't act (a mode in
-- combat), the pointer leaves its outline alone; the help still shows.
local function Hover(button, outline, held, owner, tip, below, live)
    button:SetScript("OnEnter", function()
        if not live or live() then
            paint(outline, T.accent)
        end
        if tip then
            Widgets.ShowTip(owner or button, tip, below)
        end
    end)
    button:SetScript("OnLeave", function()
        if not (held and held()) then
            paint(outline, T.border)
        end
        if tip then
            Widgets.HideTip()
        end
    end)
end

function Widgets.Label(parent, text, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setFont(fs, size or T.size.label)
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
    local fs = Widgets.Label(row, (text or ""):upper(), T.size.small, T.muted)
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    local line = row:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    line:SetHeight(1)
    fill(line, T.border)
    return row
end

----------------------------------------------------------------------------------
-- a tooltip: a line or two of help beside a control while the pointer is over it. The kit's own
-- frame, not GameTooltip, in the panel's look.
----------------------------------------------------------------------------------

local TIP_WIDTH = 240
local tip   -- one for every control, made when first shown

-- below: under owner, right edges lined up, for a control at the window's right edge.
function Widgets.ShowTip(owner, text, below)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        Widgets.Backdrop(tip, T.backdrop, T.border, 0.97)
        tip.text = Widgets.Label(tip, "")
        if type(tip.text.SetWordWrap) == "function" then tip.text:SetWordWrap(true) end
        tip.text:SetWidth(TIP_WIDTH)
        tip.text:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -8)
    end
    tip.text:SetText(text)
    tip:ClearAllPoints()
    if below then
        tip:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -6)
    else
        tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
    end
    tip:SetSize(TIP_WIDTH + 16, ceil(tip.text:GetStringHeight()) + 16)
    tip:Show()
end

function Widgets.HideTip()
    if tip then
        tip:Hide()
    end
end

-- The tooltip, once made (for tests).
function Widgets.TipFrame()
    return tip
end

----------------------------------------------------------------------------------
-- a check box: on or off. A click anywhere on its row toggles it.
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
    row.tick = tick

    function row:SetChecked(on)
        row.checked = on and true or false
        if row.checked then tick:Show() else tick:Hide() end
    end

    Hover(row, { box }, nil, row, spec.tip)

    row:SetScript("OnClick", Guard(function()
        row:SetChecked(not row.checked)
        if spec.onChange then spec.onChange(row.checked) end
    end))

    return row
end

----------------------------------------------------------------------------------
-- a dropdown: one of a list
--
-- A field showing the current choice, with a chevron. A click opens the list under it, the current
-- choice marked in the accent. A click on a row chooses it and closes the list; a click anywhere
-- else closes it unchanged, through a screen-sized catcher under the list. One list is open at a
-- time. The list belongs to the dropdown, so it closes with the panel, and reopening the panel
-- never finds it still open. Its choices can change (SetOptions); with none, the field shows
-- spec.empty, muted, and opens nothing.
----------------------------------------------------------------------------------

local openDropdown   -- the dropdown whose list is showing

-- A down-pointing triangle from four 1px rows, so it takes the theme's colour without an art file.
function Widgets.Chevron(parent)
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

    Widgets.Chevron(field):SetPoint("RIGHT", field, "RIGHT", -6, 0)

    local list = CreateFrame("Frame", nil, row)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetWidth(width)
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
    local names = spec.names
    local items = {}   -- a row for each choice, in order
    local made = {}    -- every row made, the spare ones hidden
    row.items = items

    local function name(option)
        return names and names[option] or tostring(option)
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

    -- The list's i-th row, whichever choice it holds (item.option).
    local function Item(i)
        local item = CreateFrame("Button", nil, list)
        item:SetHeight(ROW)
        item:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (i - 1) * ROW)
        item:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -1 - (i - 1) * ROW)

        item.highlight = item:CreateTexture(nil, "BACKGROUND")
        item.highlight:SetAllPoints(item)
        fill(item.highlight, T.hover)
        item.highlight:Hide()

        item.mark = item:CreateTexture(nil, "ARTWORK")
        item.mark:SetSize(2, ROW - 8)
        item.mark:SetPoint("LEFT", item, "LEFT", 3, 0)
        fill(item.mark, T.accent)

        item.text = Widgets.Label(item, "")
        item.text:SetPoint("LEFT", item, "LEFT", 10, 0)
        item.text:SetPoint("RIGHT", item, "RIGHT", -6, 0)

        item:SetScript("OnEnter", function() item.highlight:Show() end)
        item:SetScript("OnLeave", function() item.highlight:Hide() end)
        item:SetScript("OnClick", Guard(function()
            close()
            if item.option ~= value then
                row:SetValue(item.option)
                if spec.onChange then spec.onChange(item.option) end
            end
        end))
        return item
    end

    function row:SetValue(option)
        value = option
        local shown, c = spec.empty or "", T.muted
        if #items > 0 then
            shown, c = option ~= nil and name(option) or "", T.text
        end
        text:SetText(shown)
        text:SetTextColor(c[1], c[2], c[3])
        mark()
    end

    -- New choices, and new names for them if given. The field keeps its value, which the caller
    -- sets again if it went.
    function row:SetOptions(options, newNames)
        names = newNames or names
        options = options or {}
        for i, option in ipairs(options) do
            local item = made[i] or Item(i)
            made[i] = item
            item.option = option
            item.text:SetText(name(option))
            item:Show()
            items[i] = item
        end
        for i = #options + 1, #made do
            made[i]:Hide()
            items[i] = nil
        end
        list:SetHeight(#options * ROW + 2)
        row:SetValue(value)
    end

    row:SetOptions(spec.options)

    function row:Open()
        if openDropdown and openDropdown ~= row then
            openDropdown:Close()
        end
        openDropdown = row
        Widgets.HideTip()
        Widgets.ClearFocus()
        mark()
        catcher:Show()
        list:Show()
        paint(fieldEdges, T.accent)
    end

    row.Close = close

    function row:IsOpen()
        return list:IsShown()
    end

    Hover(field, fieldEdges, function() return list:IsShown() end, row, spec.tip)
    field:SetScript("OnClick", Guard(function()
        if list:IsShown() then
            close()
        elseif #items > 0 then
            row:Open()
        end
    end))

    return row
end

-- Closes the open list, if any (the panel switching pages).
function Widgets.CloseDropdown()
    if openDropdown then
        openDropdown:Close()
    end
end

----------------------------------------------------------------------------------
-- a text field
--
-- Its label on the left and the field on the right, like a dropdown. A click in it takes the
-- keyboard; Enter hands spec.onEnter what was typed, and Enter or Escape gives the keyboard back.
-- Its outline takes the accent under the pointer and while it has the keyboard. A new EditBox
-- takes the keyboard when shown unless told not to, and SetText fires OnTextChanged at once
-- (CF-121): SetAutoFocus(false) comes first.
----------------------------------------------------------------------------------

local typing   -- the text field that has the keyboard

function Widgets.Input(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW + 2)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("LEFT", row, "LEFT", 0, 0)

    local box = CreateFrame("EditBox", nil, row)
    box:SetAutoFocus(false)
    box:SetSize(spec.width or 130, ROW)
    box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    box:SetMaxLetters(spec.maxLetters or 32)
    setFont(box, T.size.label)
    box:SetTextColor(T.text[1], T.text[2], T.text[3])
    box:SetTextInsets(6, 6, 0, 0)
    local _, edges = Widgets.Backdrop(box, T.track, T.border)
    row.box = box

    Hover(box, edges, function() return typing == box end, row, spec.tip)
    box:SetScript("OnEditFocusGained", function()
        typing = box
        Widgets.HideTip()
        paint(edges, T.accent)
    end)
    box:SetScript("OnEditFocusLost", function()
        if typing == box then
            typing = nil
        end
        paint(edges, box:IsMouseOver() and T.accent or T.border)
    end)
    box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
    box:SetScript("OnEnterPressed", Guard(function()
        box:ClearFocus()
        if spec.onEnter then spec.onEnter(box:GetText() or "") end
    end))

    function row:GetValue()
        return box:GetText() or ""
    end

    function row:SetValue(text)
        box:SetText(text or "")
    end

    return row
end

-- Gives the keyboard back, if a text field has it (the panel closing or switching pages).
function Widgets.ClearFocus()
    if typing then
        typing:ClearFocus()
    end
end

----------------------------------------------------------------------------------
-- tabs: which page of a panel shows
--
-- A row of tabs over a 1px divider, each its name with padding either side. The current tab has
-- accent text and a 2px accent bar on the divider; the tab under the pointer is highlighted.
----------------------------------------------------------------------------------

function Widgets.Tabs(parent, spec)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(spec.height or 26)

    local divider = bar:CreateTexture(nil, "BORDER")
    divider:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    fill(divider, T.border)

    local value
    local tabs = {}
    bar.tabs = tabs

    local function mark()
        for _, tab in ipairs(tabs) do
            local current = tab.page == value
            if current then tab.mark:Show() else tab.mark:Hide() end
            local c = current and T.accent or T.soft
            tab.text:SetTextColor(c[1], c[2], c[3])
        end
    end

    local x = 0
    for i, page in ipairs(spec.pages) do
        local tab = CreateFrame("Button", nil, bar)
        tab.page = page

        tab.text = Widgets.Label(tab, spec.names and spec.names[page] or page, nil, T.soft, "CENTER")
        tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        local width = ceil(tab.text:GetStringWidth()) + (spec.padding or 13) * 2
        tab:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
        tab:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
        tab:SetWidth(width)
        x = x + width

        tab.highlight = tab:CreateTexture(nil, "BACKGROUND")
        tab.highlight:SetAllPoints(tab)
        fill(tab.highlight, T.hover)
        tab.highlight:Hide()

        tab.mark = tab:CreateTexture(nil, "ARTWORK")
        tab.mark:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.mark:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tab.mark:SetHeight(2)
        fill(tab.mark, T.accent)

        tab:SetScript("OnEnter", function() tab.highlight:Show() end)
        tab:SetScript("OnLeave", function() tab.highlight:Hide() end)
        tab:SetScript("OnClick", Guard(function()
            if page ~= value then
                bar:SetValue(page)
                if spec.onChange then spec.onChange(page) end
            end
        end))
        tabs[i] = tab
    end

    function bar:SetValue(page)
        value = page
        mark()
    end

    return bar
end

----------------------------------------------------------------------------------
-- a labelled slider: a number in a range, its value at the right. It snaps to its step. format
-- turns the raw value into what the reader sees.
----------------------------------------------------------------------------------

function Widgets.Slider(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SLIDER_ROW)

    local label = Widgets.Label(row, spec.label)
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)

    local value = Widgets.Label(row, "", nil, T.soft, "RIGHT")
    value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.valueText = value

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

    -- Help beside the row while the pointer is over its label or its track.
    if spec.tip then
        row:EnableMouse(true)
        for _, region in ipairs({ row, slider }) do
            region:SetScript("OnEnter", function() Widgets.ShowTip(row, spec.tip) end)
            region:SetScript("OnLeave", function() Widgets.HideTip() end)
        end
    end

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
        return floor((v - spec.min) / step + 0.5) * step + spec.min
    end

    local function show(v)
        value:SetText(spec.format and spec.format(v) or tostring(floor(v + 0.5)))
    end

    slider:SetScript("OnValueChanged", Guard(function(_, v)
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
--
-- spec.form "hex": the setting holds six hex digits; spec.get() returns them and spec.onChange
-- takes each new colour as hex. "rgb": spec.get() returns r, g, b and spec.onChange(r, g, b).
-- Without spec.get the swatch's own colour stands in for the setting.
--
-- Cancel puts back the colour the setting held when the picker opened, unless something else has
-- set it since (a reset, a page's reset or a profile switch, any of which can happen with the
-- picker still open). Then that change stands, and is what Cancel puts back after any more
-- dragging. A hex setting is compared in hex, as it is kept, so the rounding of the picker's colour
-- to hex is not taken for a change from elsewhere.
----------------------------------------------------------------------------------

function Widgets.Swatch(parent, spec)
    local form = spec.form or (type(ns.kit.config) == "table" and ns.kit.config.colours) or "rgb"

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

    function row:SetHex(hex)
        local nr, ng, nb = Theme.FromHex(hex)
        if nr then
            row:SetColor(nr, ng, nb)
        end
    end

    Hover(row, { frame }, nil, row, spec.tip)

    local function picker(base, now, changed, write)
        -- base: the opening colour, as the setting keeps it; now(): the setting's colour now;
        -- write(v): sets the swatch and calls onChange
        local wrote = base
        local r0, g0, b0
        if form == "hex" then
            r0, g0, b0 = Theme.FromHex(base)
        else
            r0, g0, b0 = base[1], base[2], base[3]
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0,
            hasOpacity = false,
            swatchFunc = Guard(function()
                if changed(now(), wrote) then
                    base = now()
                end
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                if form == "hex" then
                    wrote = Theme.ToHex(nr, ng, nb)
                else
                    wrote = { nr, ng, nb }
                end
                write(wrote)
            end),
            cancelFunc = Guard(function()
                if not changed(now(), wrote) then
                    write(base)
                end
            end),
        })
    end

    row:SetScript("OnClick", Guard(function()
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then
            Init.Print("the colour picker is not available on this client")
            return
        end
        if form == "hex" then
            local function now()
                if spec.get then
                    return spec.get()
                end
                return Theme.ToHex(r, g, b)
            end
            picker(now(), now, function(a, w) return a ~= w end, function(hex)
                row:SetHex(hex)
                if spec.onChange then spec.onChange(hex) end
            end)
        else
            local function now()
                if spec.get then
                    return { spec.get() }
                end
                return { r, g, b }
            end
            picker(now(), now, function(a, w)
                return a[1] ~= w[1] or a[2] ~= w[2] or a[3] ~= w[3]
            end, function(c)
                row:SetColor(c[1], c[2], c[3])
                if spec.onChange then spec.onChange(c[1], c[2], c[3]) end
            end)
        end
    end))

    return row
end

----------------------------------------------------------------------------------
-- a button: an action, never a setting
--
-- A primary button is the one a dialog expects you to press: accent outline and label at rest,
-- and a lighter fill on hover. There is at most one per dialog.
----------------------------------------------------------------------------------

-- Pressed: the label sinks a pixel.
local function Press(button, label)
    button:SetScript("OnMouseDown", function() label:SetPoint("CENTER", button, "CENTER", 0, -1) end)
    button:SetScript("OnMouseUp", function() label:SetPoint("CENTER", button, "CENTER", 0, 0) end)
end
Widgets.Press = Press

-- Dresses a Button in the theme without touching its OnClick, so it can dress a button made from
-- a template whose click handler must stay Blizzard's (Kit/ReloadDialog.lua).
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
    Press(button, label)
    return button
end

function Widgets.Button(parent, text, onClick, width, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 90, ROW + 2)
    Widgets.StyleButton(button, text, primary)
    button:SetScript("OnClick", Guard(onClick))
    return button
end

----------------------------------------------------------------------------------
-- a mode button: a temporary mode, which isn't saved (unlocking frames, a test, a mock)
--
-- It says what a click does: spec.start while the mode is off, spec.stop while it is on, and keeps
-- the accent on its outline and label while the mode is on. spec.onChange(on) asks for the mode
-- and returns whether it is on afterwards, which the button shows, so a refusal leaves it as it
-- was. While the mode can't be had (in combat), SetAvailable(false) mutes the label and the
-- pointer lights nothing, though the help still shows and a click still asks, for chat to say why.
----------------------------------------------------------------------------------

function Widgets.ModeButton(parent, spec)
    local button = CreateFrame("Button", nil, parent)
    button:SetHeight(ROW + 2)
    local _, edges = Widgets.Backdrop(button, T.track, T.border)
    local label = Widgets.Label(button, spec.start, nil, T.text, "CENTER")
    label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label = label
    button.edges = edges
    button.on = false
    button.available = true

    local function mark()
        label:SetText(button.on and spec.stop or spec.start)
        local c = not button.available and T.muted or button.on and T.accent or T.text
        label:SetTextColor(c[1], c[2], c[3])
        local lit = button.available and (button.on or button:IsMouseOver())
        paint(edges, lit and T.accent or T.border)
    end

    function button:SetOn(on)
        button.on = on and true or false
        mark()
    end

    function button:SetAvailable(available)
        button.available = available and true or false
        mark()
    end

    Hover(button, edges, function() return button.on end, button, spec.tip, spec.tipBelow,
        function() return button.available end)
    Press(button, label)
    button:SetScript("OnClick", Guard(function()
        button:SetOn(spec.onChange(not button.on))
    end))
    return button
end
