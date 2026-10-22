local addonName, ns = ...

-- Shown while unlocked so both filled and empty styling are visible.
local PREVIEW_POINTS = 3

-- SetValue's optional second argument, for animated fills. Both members are looked up
-- once, here: the argument can't be nil, so a member this build lacks would make every
-- update raise. Without both the bar doesn't animate, and SetValue gets the count alone,
-- which snaps (the client's default, Immediate).
local Interpolation = Enum.StatusBarInterpolation
local EASE = Interpolation and Interpolation.ExponentialEaseOut
local SNAP = Interpolation and Interpolation.Immediate
local canSmooth = EASE ~= nil and SNAP ~= nil
ns.canSmooth = canSmooth

local frame
local pips = {}

-- The border sits inside the pip, so it never reaches a neighbour whatever the spacing,
-- and the frame's size (and clamping to the screen) includes it.
local function CreateBorder(holder)
    local left = holder:CreateTexture(nil, "BORDER")
    left:SetPoint("TOPLEFT", holder, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT")

    local right = holder:CreateTexture(nil, "BORDER")
    right:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")

    local top = holder:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", left, "TOPRIGHT")
    top:SetPoint("TOPRIGHT", right, "TOPLEFT")

    local bottom = holder:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    holder.border = { left = left, right = right, top = top, bottom = bottom }
end

-- Each bar covers one point of the range, so the client renders it empty below that
-- point and full at or above it without us reading the count.
local function CreatePointBar(parent, index)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(index - 1, index)
    bar:SetValue(0)
    return bar
end

local function CreatePip(index)
    -- The holder carries the background and border. The StatusBars only receive the
    -- secret value, and the only thing anchored to one is the clip frame below, so
    -- their secret state never spreads into the rest of the layout.
    local holder = CreateFrame("Frame", nil, frame)
    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints()
    CreateBorder(holder)

    -- The count can't be compared, so a gain can't be told from a spend to choose the
    -- interpolation. Instead every value goes to two bars: an invisible one that eases,
    -- and the visible one that snaps, drawn only inside the eased bar's fill. What shows
    -- is the smaller of the two, so a gain eases in and a spend empties at once.
    local reveal = CreatePointBar(holder, index)
    reveal:SetStatusBarTexture(ns.textures.flat.path)
    reveal:SetStatusBarColor(0, 0, 0, 0)

    local clip = CreateFrame("Frame", nil, holder)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(reveal:GetStatusBarTexture())

    holder.reveal = reveal
    holder.bar = CreatePointBar(clip, index)

    return holder
end

function ns:CreateComboBar()
    frame = CreateFrame("Frame", "gRogueComboFrame", UIParent)
    frame:SetDontSavePosition(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        local db = ns.db
        db.point, db.relativePoint = point, relativePoint
        db.x, db.y = x * db.scale, y * db.scale
    end)

    frame.mover = frame:CreateTexture(nil, "BACKGROUND")
    frame.mover:SetPoint("TOPLEFT", -4, 4)
    frame.mover:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.mover:SetColorTexture(0.2, 0.8, 0.2, 0.35)

    frame.moverLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.moverLabel:SetPoint("BOTTOM", frame, "TOP", 0, 6)
    frame.moverLabel:SetText("gRogue - drag to move")

    for i = 1, ns.MAX_POINTS do
        pips[i] = CreatePip(i)
    end

    self.frame = frame
end

function ns:ApplyLayout()
    local db = self.db
    local count = self.MAX_POINTS
    local width, height, gap = db.pipWidth, db.pipHeight, db.spacing
    local vertical = db.orientation == "VERTICAL"
    local texture = (self.textures[db.texture] or self.textures.flat).path
    local empty, edge = db.emptyColor, db.borderColor
    -- Leave at least a pixel of fill however small the pip.
    local inset = db.border and math.min(db.borderSize, math.floor((math.min(width, height) - 1) / 2)) or 0

    -- The position is saved in UIParent units, but SetPoint takes offsets in the frame's
    -- own scaled units; dividing keeps the bar in place when the scale changes.
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relativePoint, db.x / db.scale, db.y / db.scale)
    frame:SetScale(db.scale)
    frame:SetAlpha(db.alpha)
    if vertical then
        frame:SetSize(width, count * height + (count - 1) * gap)
    else
        frame:SetSize(count * width + (count - 1) * gap, height)
    end

    for i, pip in ipairs(pips) do
        local slot = db.reverse and (count - i) or (i - 1)
        pip:ClearAllPoints()
        pip:SetSize(width, height)
        if vertical then
            pip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, slot * (height + gap))
        else
            pip:SetPoint("TOPLEFT", frame, "TOPLEFT", slot * (width + gap), 0)
        end

        -- Both bars share a rect and fill direction, so the clip grows over the fill.
        for _, bar in ipairs({ pip.reveal, pip.bar }) do
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", pip, "TOPLEFT", inset, -inset)
            bar:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", -inset, inset)
            bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
            bar:SetReverseFill(db.reverse)
        end

        local fill = db.usePipColors and db.pipColors[i] or db.fillColor
        pip.bar:SetStatusBarTexture(texture)
        pip.bar:SetStatusBarColor(fill.r, fill.g, fill.b)
        pip.bg:SetColorTexture(empty.r, empty.g, empty.b, db.emptyAlpha)

        local border = pip.border
        border.left:SetWidth(inset)
        border.right:SetWidth(inset)
        border.top:SetHeight(inset)
        border.bottom:SetHeight(inset)
        for _, side in pairs(border) do
            side:SetColorTexture(edge.r, edge.g, edge.b)
            side:SetShown(db.border)
        end
    end
end

function ns:UpdateVisibility()
    local db = self.db
    local unlocked = not db.locked

    frame:EnableMouse(unlocked)
    frame.mover:SetShown(unlocked)
    frame.moverLabel:SetShown(unlocked)

    local shown = unlocked
        or ((not db.hideWithoutTarget or UnitExists("target"))
            and (not db.hideOutOfCombat or self.inCombat))
    frame:SetShown(shown)
end

function ns:UpdatePoints()
    -- GetComboPoints is what Blizzard's own ComboFrame reads; UnitPower still reports
    -- the previous target's count when PLAYER_TARGET_CHANGED fires. For addon code the
    -- result is a secret: it may only be handed to a widget that accepts secrets, never
    -- compared, tested or used in arithmetic.
    local points = PREVIEW_POINTS
    if self.db.locked then
        points = GetComboPoints("player", "target")
    end

    if not canSmooth then
        for _, pip in ipairs(pips) do
            pip.reveal:SetValue(points)
            pip.bar:SetValue(points)
        end
        return
    end
    local ease = self.db.smooth and EASE or SNAP
    for _, pip in ipairs(pips) do
        pip.reveal:SetValue(points, ease)
        pip.bar:SetValue(points, SNAP)
    end
end

function ns:Refresh()
    self:ApplyLayout()
    self:UpdateVisibility()
    self:UpdatePoints()
end
