# gRogue

A customizable combo point display for **WoW: Forever** (client 1.60.1, interface 16001): a bar of five points that fill as a rogue builds combo points on the target, with its size, shape, colours, texture and visibility as settings. Rogues only. The repo root is the addon: its TOC is `gRogue.toc`.

- [docs/SPEC.md](docs/SPEC.md) is what gRogue does, as built: the bar, the count, when it shows, every setting with its default and range, the commands, the saved data, how the bar is built, the settings window, the client facts behind it, the decisions and the open questions.
- [README.md](README.md) is the short version for players.
- gRogue uses gkit's runtime, like gFrames and gBars, and its settings window follows gFrames' design rules (gFrames' docs/SPEC.md, UI design rules).

## Rules

- The user commits. Don't commit, stage or push unless asked.
- `Kit/` is gkit's runtime (`forever-addons/gkit`): Init, Theme, Config and Widgets. Never edit a file there.
  - A fix goes into gkit's `runtime/`, with its test, and comes over with `luajit <gkit>/tools/sync.lua .`, run from the repo root. Then run the smoke tests again.
  - `tools/smoke.sh` fails on an edited copy, and on a TOC that doesn't load the copies together and in gkit's order (gkit's `tools/kit-lint.lua` against `Kit/MANIFEST.lock`).
  - `KitSetup.lua` tells the kit what is gRogue's own (its name, save, chat colour, the window's palette, how many errors print, how settings are checked). The TOC loads it first, then `Kit/`, then gRogue's own files.
- Line endings: the checkout is CRLF (`core.autocrlf` is true), except shell scripts, which `.gitattributes` keeps LF because bash rejects a CRLF script. Keep each file's line endings: `sed -i` and some scripts strip them, so check that `git diff --stat` shows only your lines.
- A TOC change, a file added or removed, needs a client restart, not a `/reload`.
- Update docs/SPEC.md and README.md in the same change whenever a command, setting, default or setup step changes.
- Comments cite docs/SPEC.md by section name, never by number, and client facts by gkit's registry number (gkit CF-...).

## Commands

- `bash tools/smoke.sh` runs the whole harness. Run it before finishing any change. It needs LuaJIT 2.1 (WoW's Lua is 5.1) and gkit's checkout beside this one (`forever-addons/gkit`, found from here or from a worktree under `forever-addons/_worktrees`; `GKIT=<folder>` names another). In order, it:
  - compiles every file `gRogue.toc` loads;
  - lints `Kit/` with gkit's `tools/kit-lint.lua`;
  - runs `tools/smoke.lua` against `tools/stub_wow.lua`: the non-rogue path, settings over a save and saves it can't use, the bar's layout and its secret count, dragging, when the bar shows, the settings window, `/grogue`, the addon compartment, and clients without the interpolation enum or a member of it, without `GetComboPoints` or without the vehicle events.
- `SMOKE_VERBOSE=1` prints the addon's chat output too.
- The stub's frames are loose: a method it doesn't model is a no-op. Its secrets throw on comparison, arithmetic, concatenation and indexing, and it records any method but `SetValue` handed one, and any read of a bar's value while it holds one. Lua can't make a secret throw on `==` against a number or in a truth test, so those stay out by review. A pass says the logic holds against the stub, not how anything looks.
- The client is set through globals the smoke flips (`playerClass`, `targetExists`, `inCombat`, `inVehicle`, `comboPoints`, `GetComboPoints`, `Enum`, `missingEvents`); `gRogueDB` is the save the next session loads.
- When a new client build comes, launch day's included, gkit's API audit (`tools/api-audit.sh` in gkit) checks everything gRogue uses against that build's UI source.

## Layout

```
gRogue.toc        the load order: KitSetup.lua, Kit/, Core.lua, ComboBar.lua, UI/Options.lua;
                  the compartment lines; SavedVariables gRogueDB
KitSetup.lua      what gRogue tells the kit
Kit/              gkit's runtime, synced in: Init (output, the guard, events), Theme, Config (the
                  checks on saved values), Widgets (the window's controls); MANIFEST.lock
Core.lua          the settings (defaults, limits, lists), the save loaded and checked, the events,
                  /grogue and the addon compartment's handlers
ComboBar.lua      the bar: its points, layout, visibility and the count
UI/Options.lua    the settings window
tools/            smoke.sh, smoke.lua, stub_wow.lua
docs/SPEC.md
```

## Conventions

- The count is a secret: it goes to `StatusBar:SetValue` and nowhere else (docs/SPEC.md, How the bar is built). Never compare it, test it, do arithmetic with it, or read a bar holding it back.
- A new setting gets its default in `ns.defaults` (`Core.lua`), with its range in `ns.limits` or its list in `ns.choices`, which the kit's Config checks saved values against. Its control goes in `UI/Options.lua`, and a slider spans the range. Then docs/SPEC.md, Settings.
- A setting changes through `ns:Set`, which refreshes the bar; a colour is changed in its table and the bar refreshed.
- Every handler, script and command goes through `ns.Guard`, and every event through `ns.On`, which registers under `pcall`.
- Colours in the window come from the kit's tokens (`ns.kit.tokens.panel`, KitSetup.lua), gFrames' palette with the rogue's yellow as the accent; the bar's colours are settings.
- gRogue touches no Blizzard frame but `ColorPickerFrame` and `GameTooltip`.

## Pitfalls

Each is a rule with the reason behind it. docs/SPEC.md, Client facts, has the facts.

- Read the count with `GetComboPoints("player", "target")`, never `UnitPower` while it exists: `UnitPower` still reports the previous target's count when `PLAYER_TARGET_CHANGED` fires.
- Don't filter `UNIT_POWER_FREQUENT` by its power token: the token for combo points is unverified on this client (gkit CF-059), and a wrong one stops the bar updating at all.
- Look `Enum.StatusBarInterpolation`'s members up once and pass `SetValue` its second argument only when both exist: it can't be nil, so a missing member would make every update raise.
- Take combat from `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`, not `InCombatLockdown()`, which is still false inside the first.
- Guard drag scripts too: the client's error frame is off by default, so an error there would vanish, and the bar's new place with it.
- Save the bar's offset times its scale, and divide by it when placing: `SetPoint` takes offsets in the frame's own scaled units, so the bar would move when the scale changes.
- Close an open colour picker before a reset: its Cancel would write the old colour into the fresh defaults.
- A saved `false` is a value: fill only what is missing (`nil`), never what is false.
- Anchor nothing to a bar holding the count but its clip frame, so the bar's secret state never spreads into the layout.

## In-game testing

- Link the repo into the client's AddOns folder as `gRogue` with a directory junction (README.md, Install), so an edit is live after `/reload`.
- Test on a rogue; on any other class gRogue makes no bar. `/grogue unlock` shows the bar with three made-up points, filled and empty both, wherever the hide settings would hide it.
- Turn on `/console scriptErrors 1` while working. gRogue prints each error in chat itself, so a session with none in chat is clean.
- The open questions in docs/SPEC.md, Open questions, are for a session in game.

## Launch

- On launch day, a new build: run gkit's API audit against the launch build's UI source and triage gRogue's hits, then a session in game on a rogue. Check that smooth fill is still offered (gkit CF-136: a renamed member takes it out of the window) and that the bar follows combo points as they build and spend.
