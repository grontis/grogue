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

-- Each number's range, which its slider spans (UI/Options.lua shows a percent's times
-- 100). Saved values are held to it too.
ns.limits = {
    pipWidth = { 4, 100 },
    pipHeight = { 4, 100 },
    spacing = { 0, 30 },
    scale = { 0.5, 2 },
    alpha = { 0.1, 1 },
    emptyAlpha = { 0, 1 },
    borderSize = { 1, 6 },
}

-- Settings limited to a list of values. A dropdown offers exactly its list.
local ANCHORS = {
    "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
ns.choices = {
    point = ANCHORS,
    relativePoint = ANCHORS,
    orientation = { "HORIZONTAL", "VERTICAL" },
    texture = ns.textureOrder,
}

-- The kit's Config checks saved values against these (KitSetup.lua: checking only, as gRogueDB
-- stays gRogue's own).
ns.kit.config.defaults = ns.defaults
ns.kit.config.limits = ns.limits
ns.kit.config.choices = ns.choices

----------------------------------------------------------------------------------
-- output and error containment
--
-- The kit's (Kit/Init.lua): ns.Print, and ns.Guard around every handler, script and
-- command. The client's error frame is off by default (/console scriptErrors 1), so an
-- error in one of our handlers would otherwise vanish: each distinct error prints once,
-- up to the 50 kept (KitSetup.lua); past them errors are only counted.
----------------------------------------------------------------------------------

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

-- A saved value is used only if the kit's Config (Kit/Config.lua) allows it: the default's
-- type, in the setting's range, on its list. A number without a range (an offset) must still be
-- finite; NaN fails every comparison. A colour, as the picker gives it, has r, g and b, each a
-- number from 0 to 1.
local Config = ns.Config

-- Drops each saved setting this version can't use, for CopyDefaults to fill like a missing
-- one: one bad value (a hand edit, a half-written file, a key whose type changed) would
-- otherwise break every layout refresh. A point's colour is checked on its own. Returns
-- the names dropped, sorted.
local function DropUnusable(saved)
    local dropped = {}
    for key in pairs(ns.defaults) do
        local value = saved[key]
        local bad = false
        if key == "pipColors" and type(value) == "table" then
            for i = 1, ns.MAX_POINTS do
                if value[i] ~= nil and not Config.ValidEntry(key, i, value[i]) then
                    value[i] = nil
                    bad = true
                end
            end
        elseif value ~= nil and not Config.Valid(key, value) then
            saved[key] = nil
            bad = true
        end
        if bad then
            dropped[#dropped + 1] = key
        end
    end
    table.sort(dropped)
    return dropped
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

-- Never a secret: Forever's API docs give UnitInVehicle no secret return.
local function InVehicle()
    return UnitInVehicle and UnitInVehicle("player") or false
end

-- The kit's event router (Kit/Init.lua): registration under pcall, since an event this
-- build lacks throws on registration ("could not register" is printed, and the bar works
-- without it); a unit passed is a RegisterUnitEvent; every handler guarded. A blocked or
-- forbidden action is silent to Lua, so the kit says so if one names us.
local On = ns.On

local function OnAddonLoaded(_, name)
    if name ~= addonName then
        return
    end
    ns.Off("ADDON_LOADED", OnAddonLoaded)

    -- SavedVariables are read just before this. A save that isn't a table, and a setting
    -- this version can't use, give way to the defaults, and say so.
    if gRogueDB ~= nil and type(gRogueDB) ~= "table" then
        gRogueDB = nil
        ns.Print("saved settings unreadable; using the defaults.")
    end
    gRogueDB = gRogueDB or {}
    local dropped = DropUnusable(gRogueDB)
    if #dropped > 0 then
        ns.Print("reset saved settings this version can't use: " .. table.concat(dropped, ", ") .. ".")
    end
    CopyDefaults(ns.defaults, gRogueDB)
    ns.db = gRogueDB

    local _, class = UnitClass("player")
    if class ~= "ROGUE" then
        return
    end

    ns.inCombat = InCombatLockdown()
    ns.inVehicle = InVehicle()
    ns:CreateComboBar()

    -- The vehicle state is read again at each loading screen, so a ride that ends behind
    -- one can't leave the bar hidden.
    On("PLAYER_ENTERING_WORLD", function()
        ns.inVehicle = InVehicle()
        ns:Refresh()
    end)
    -- Combo points live on the target, so a target swap changes the count without any
    -- power event firing.
    On("PLAYER_TARGET_CHANGED", function()
        ns:UpdateVisibility()
        ns:UpdatePoints()
    end)
    -- Every player power change lands here, energy ticks included, as in Blizzard's own
    -- ComboFrame. The event's powerType could skip all but combo points, but its token on
    -- this client is unverified (GR-L2, probe Q17 in forever-addons/OPEN-CLIENT-PROBES.md),
    -- and a wrong one would stop the bar updating at all.
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
    -- In a vehicle the player's own combo points don't apply: hidden until they get out.
    On("UNIT_ENTERED_VEHICLE", function()
        ns.inVehicle = true
        ns:UpdateVisibility()
    end, "player")
    On("UNIT_EXITED_VEHICLE", function()
        ns.inVehicle = false
        ns:UpdateVisibility()
    end, "player")
end
On("ADDON_LOADED", OnAddonLoaded)

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
