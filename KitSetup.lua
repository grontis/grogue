-- KitSetup.lua -- what gRogue tells the kit, read by the files in Kit/ as they load.
--
-- Kit/ holds gkit's runtime, copied in by gkit's tools/sync.lua with Kit/MANIFEST.lock beside it;
-- tools/smoke.sh runs gkit's tools/kit-lint.lua, which fails on any copy edited here. A fix to a
-- Kit/ file is made in gkit and synced. The TOC loads this file first, then Kit/, then gRogue's
-- own files. A TOC change, a file added or removed, needs a client restart, not a /reload.

local addonName, ns = ...

ns.kit = {
    name = "gRogue",
    db = "gRogueDB",
    prefixColor = "fff569",
    -- gRogue has no command that lists errors, so each error it keeps (50) prints in full, as
    -- every distinct error always has here; the kit's terse count line would point nowhere.
    printedErrors = 50,

    -- The settings window's palette (Kit/Widgets.lua reads it as it loads): gFrames' panel, with
    -- the rogue's class yellow as its accent, as gRogue's name is in chat.
    tokens = {
        panel = {
            backdrop = { 0.06, 0.06, 0.07 },
            header   = { 0.10, 0.10, 0.12 },
            border   = { 0.24, 0.24, 0.27 },
            track    = { 0.12, 0.12, 0.14 },   -- inside a control: box, field, button, slider track
            hover    = { 0.17, 0.17, 0.20 },   -- a list row under the pointer
            accent   = { 1.00, 0.96, 0.41 },
            text     = { 0.92, 0.92, 0.92 },
            soft     = { 0.70, 0.70, 0.72 },
            muted    = { 0.50, 0.50, 0.53 },
            size     = { title = 14, label = 12, small = 10 },
        },
    },

    -- The window's font: the client's own, which a font string takes as it is.
    widgets = {
        font = STANDARD_TEXT_FONT,
    },

    -- Saved settings are checked by the kit's Config (Kit/Config.lua) and nothing more: gRogueDB
    -- stays gRogue's own, every setting in it and its unknown keys left alone (store = false).
    -- Core.lua hands it the defaults, limits and lists. A colour is { r, g, b }, each 0 to 1.
    config = {
        colours = "rgb",
        store = false,
    },
}
