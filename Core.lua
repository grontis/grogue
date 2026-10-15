local addonName, ns = ...

ns.MAX_POINTS = 5

ns.textures = {
    flat     = { label = "Flat",     path = [[Interface\Buttons\WHITE8X8]] },
    blizzard = { label = "Blizzard", path = [[Interface\TargetingFrame\UI-StatusBar]] },
    raid     = { label = "Raid",     path = [[Interface\RaidFrame\Raid-Bar-Hp-Fill]] },
}
ns.textureOrder = { "flat", "blizzard", "raid" }

ns.defaults = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -180,
    locked = true,

    orientation = "HORIZONTAL",
    reverse = false,
    pipWidth = 30,
    pipHeight = 12,
    spacing = 4,
    scale = 1,
    alpha = 1,

    texture = "flat",
    smooth = true,
    fillColor = { r = 1, g = 0.82, b = 0 },
    emptyColor = { r = 0, g = 0, b = 0 },
    emptyAlpha = 0.5,
    border = true,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0 },
    usePipColors = false,
    pipColors = {
        { r = 1,   g = 0.9,  b = 0.2 },
        { r = 1,   g = 0.75, b = 0.15 },
        { r = 1,   g = 0.6,  b = 0.1 },
        { r = 1,   g = 0.4,  b = 0.1 },
        { r = 0.9, g = 0.15, b = 0.1 },
    },

    hideWithoutTarget = false,
    hideOutOfCombat = false,
}

----------------------------------------------------------------------------------
-- output and error containment
--
-- The client's error frame is off by default (/console scriptErrors 1), so an error in
-- one of our handlers would otherwise vanish. Each distinct error prints once.
----------------------------------------------------------------------------------

local PREFIX = "|cfffff569gRogue|r: "

function ns.Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end

local seenErrors = {}

function ns.Guard(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            err = tostring(err)
            if not seenErrors[err] then
                seenErrors[err] = true
                ns.Print("|cffff5555error|r " .. err)
            end
        end
    end
end

----------------------------------------------------------------------------------
-- settings
----------------------------------------------------------------------------------

local function CopyDefaults(src, dst)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            CopyDefaults(value, dst[key])
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

-- Sliders report every pixel of a drag, most of which snap to the value already set.
function ns:Set(key, value)
    if self.db[key] == value then
        return
    end
    self.db[key] = value
    self:Refresh()
end

function ns:SetLocked(locked)
    self:Set("locked", locked)
    ns.Options.Refresh()
end

-- Wipes in place so everything holding ns.db keeps the same table. An open colour picker
-- is closed first, or its Cancel would write the old colour into the fresh defaults;
-- Hide() does not run Cancel.
function ns:ResetSettings()
    if ColorPickerFrame and ColorPickerFrame:IsShown() then
        ColorPickerFrame:Hide()
    end
    wipe(self.db)
    CopyDefaults(self.defaults, self.db)
    self:Refresh()
    ns.Options.Refresh()
    ns.Print("settings reset to defaults.")
end

----------------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

-- An event this build lacks throws on registration instead of returning an error.
local function On(event, fn, unit)
    local ok, err
    if unit then
        ok, err = pcall(events.RegisterUnitEvent, events, event, unit)
    else
        ok, err = pcall(events.RegisterEvent, events, event)
    end
    if not ok then
        ns.Print("could not register " .. event .. ": " .. tostring(err))
        return
    end
    handlers[event] = ns.Guard(fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](event, ...)
end)

-- A blocked or forbidden action is silent to Lua, so say so if one names us.
local function OnBlocked(event, blamed, func)
    if blamed == addonName then
        ns.Print("|cffff5555" .. event .. "|r " .. tostring(func))
    end
end
On("ADDON_ACTION_BLOCKED", OnBlocked)
On("ADDON_ACTION_FORBIDDEN", OnBlocked)

On("ADDON_LOADED", function(_, name)
    if name ~= addonName then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")

    gRogueDB = gRogueDB or {}
    CopyDefaults(ns.defaults, gRogueDB)
    ns.db = gRogueDB

    local _, class = UnitClass("player")
    if class ~= "ROGUE" then
        return
    end

    ns.inCombat = InCombatLockdown()
    ns:CreateComboBar()

    On("PLAYER_ENTERING_WORLD", function()
        ns:Refresh()
    end)
    -- Combo points live on the target, so a target swap changes the count without any
    -- power event firing.
    On("PLAYER_TARGET_CHANGED", function()
        ns:UpdateVisibility()
        ns:UpdatePoints()
    end)
    On("UNIT_POWER_FREQUENT", function()
        ns:UpdatePoints()
    end, "player")
    -- InCombatLockdown() is still false inside PLAYER_REGEN_DISABLED on this client, so
    -- the events themselves are the combat state.
    On("PLAYER_REGEN_DISABLED", function()
        ns.inCombat = true
        ns:UpdateVisibility()
    end)
    On("PLAYER_REGEN_ENABLED", function()
        ns.inCombat = false
        ns:UpdateVisibility()
    end)
end)

----------------------------------------------------------------------------------
-- commands
----------------------------------------------------------------------------------

SLASH_GROGUE1 = "/grogue"
SlashCmdList.GROGUE = ns.Guard(function(msg)
    if not ns.frame then
        ns.Print("only active on rogues.")
        return
    end

    local cmd = strlower(strtrim(msg or ""))
    if cmd == "" or cmd == "config" then
        ns.Options.Toggle()
    elseif cmd == "unlock" then
        ns:SetLocked(false)
        ns.Print("unlocked. Drag to move, then /grogue lock.")
    elseif cmd == "lock" then
        ns:SetLocked(true)
        ns.Print("locked.")
    elseif cmd == "reset" then
        ns:ResetSettings()
    else
        ns.Print("/grogue [config | unlock | lock | reset]")
    end
end)

-- The addon list on the minimap (## AddonCompartmentFunc in the TOC): a click opens the
-- settings, and hovering says so, or says gRogue does nothing on this character.
function gRogue_OnAddonCompartmentClick()
    SlashCmdList.GROGUE("")
end

function gRogue_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("gRogue")
    GameTooltip:AddLine(ns.frame and "Click for settings" or "Only active on rogues", 1, 1, 1)
    GameTooltip:Show()
end

function gRogue_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
