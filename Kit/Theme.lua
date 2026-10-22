-- gkit Theme.lua @ db2bf7a: edit gkit, not this copy
-- Theme.lua -- colours from the addon's tokens.
--
-- Needs Kit/Init.lua. The kit holds no colours of its own: every colour comes from ns.kit.tokens,
-- which the addon supplies. A token is any of
--   { r = 0.31, g = 0.64, b = 0.82, a = 1 }    (a hex = "4FA3D1" beside them is ignored)
--   { 0.31, 0.64, 0.82 [, a] }
--   "4FA3D1" or "#4FA3D1"
-- and a group of them is a table: tokens.panel is the settings panel's palette (Kit/Widgets.lua),
-- the rest is the addon's own. Tokens are read when asked for, so an addon may add groups to
-- ns.kit.tokens in its own files, after the kit has loaded.
--
-- On ns.Theme (and ns.Kit.Theme, which an addon's own code cannot replace):
--   FromHex(hex)                r, g, b from 0 to 1, or nil when hex is not six hex digits
--   ToHex(r, g, b)              "RRGGBB", each channel held to 0..1 and rounded to the nearest
--   Token(path)                 the token at a dotted path in ns.kit.tokens ("panel.accent"), or nil
--   Color(token)                r, g, b, a from a token, a hex string or a dotted path (a defaults
--                               to 1); nil when it is none of those
--   Paint(texture, token [, alpha])   texture:SetColorTexture in that colour, at alpha if given
--
-- The tokens are the addon's constants, never values the client handed over, so nothing here asks
-- whether a value is secret.

local addonName, ns = ...

local Kit = ns.Kit
if not (Kit and Kit.Init) then
    error("gkit: Kit/Init.lua must load before Kit/Theme.lua", 0)
end

local type, tonumber = type, tonumber
local floor, min, max = math.floor, math.min, math.max

local Theme = {}
Kit.Theme = Theme
ns.Theme = Theme

function Theme.FromHex(hex)
    if type(hex) ~= "string" then
        return nil
    end
    local r, g, b = hex:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then
        return nil
    end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function byte(v)
    return floor(min(max(v, 0), 1) * 255 + 0.5)
end

function Theme.ToHex(r, g, b)
    return ("%02X%02X%02X"):format(byte(r), byte(g), byte(b))
end

function Theme.Token(path)
    local node = ns.kit.tokens
    if type(path) ~= "string" or type(node) ~= "table" then
        return nil
    end
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        node = node[part]
    end
    return node
end

function Theme.Color(token)
    if type(token) == "string" then
        local r, g, b = Theme.FromHex(token)
        if r then
            return r, g, b, 1
        end
        token = Theme.Token(token)
    end
    if type(token) ~= "table" then
        return nil
    end
    if type(token.r) == "number" then
        return token.r, token.g, token.b, token.a or 1
    end
    if type(token[1]) == "number" then
        return token[1], token[2], token[3], token[4] or 1
    end
    return nil
end

function Theme.Paint(texture, token, alpha)
    local r, g, b, a = Theme.Color(token)
    if r == nil then
        error("gkit Theme.Paint: not a colour: " .. tostring(token), 2)
    end
    texture:SetColorTexture(r, g, b, alpha or a)
end
