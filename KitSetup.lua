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
}
