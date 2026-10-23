# gRogue: spec

What gRogue is and does, as built. [CLAUDE.md](../CLAUDE.md) says how to work on it, and the
[README](../README.md) is the short version.

## Overview

gRogue is a customizable combo point display for WoW Forever (client 1.60.1, interface 16001):
a bar of five points that fill as a rogue builds combo points on the target. Its size, shape,
colours, texture and when it shows are settings, in a window of its own.

The client hands addons the combo point count as a secret value: it can be passed to a widget
that takes secrets, but comparing, testing or doing arithmetic on it throws. The bar is built so
that it never needs to read the count ([How the bar is built](#how-the-bar-is-built)).

### Scope

- Rogues only. On any other class gRogue makes no bar, and `/grogue` and the addon list on the
  minimap say it is only active on rogues.
- Five points.
- The bar, its settings window, `/grogue`, and its own place on the screen, dragged while
  unlocked.

### Not covered

- Blizzard's own combo point display. gRogue touches no Blizzard frame but the colour picker and
  the tooltip, so it neither hides nor restyles Blizzard's.
- Profiles. One set of settings for the whole account.
- A status command or a saved report. Errors print in chat ([Errors](#errors)).

## Features

### The bar

- Five points side by side (`HORIZONTAL`) or one above another (`VERTICAL`), `spacing` apart,
  each `pipWidth` by `pipHeight`. Point 1 is at the left, or at the bottom; with `reverse` it is
  at the right, or at the top, and each point fills from that end.
- Each point has a background in the empty colour at the empty opacity and, with `border` on, a
  border drawn inside the point, so it never reaches a neighbour whatever the spacing. The fill
  is inset by the border, which is held so at least a pixel of fill is left however small the
  point.
- The fill is one colour (`fillColor`), or a colour for each point (`usePipColors`, on by
  default: yellow to red).
- The fill's texture is `flat` (a plain colour), `blizzard` (Blizzard's status bar,
  `Interface\TargetingFrame\UI-StatusBar`) or `raid` (`Interface\RaidFrame\Raid-Bar-Hp-Fill`).
- The whole bar has a scale and an opacity of its own.
- **Smooth fill.** A point gained eases in, and a spend empties at once. Each point is two bars:
  an invisible one that eases and the visible one that snaps, drawn only inside the eased bar's
  fill, so what shows is the smaller of the two. Smooth fill is offered only where the client has
  `Enum.StatusBarInterpolation`'s `ExponentialEaseOut` and `Immediate`; without both the bar
  snaps, and the setting isn't in the window.

### The count

- The count on the target, from `GetComboPoints("player", "target")`, which Blizzard's own
  combo frame reads. On a build without it, `UnitPower("player", Enum.PowerType.ComboPoints)`,
  which still reports the previous target's count when the target changes.
- It is read again when the target changes and on every power change of the player's
  (`UNIT_POWER_FREQUENT`), energy ticks included, as Blizzard's own combo frame does.
- While the bar is unlocked, every point shows a made-up count of 3, so both the filled and the
  empty look show.

### When the bar shows

- Always while unlocked.
- Locked: hidden in a vehicle, where the player's own combo points don't apply; with
  `hideWithoutTarget` on, hidden without a target; with `hideOutOfCombat` on, hidden out of
  combat. Both are on by default, so the bar shows in combat with a target.
- Combat starts and ends with `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`, and a reload
  in combat starts in combat.
- The vehicle state follows `UNIT_ENTERED_VEHICLE` and `UNIT_EXITED_VEHICLE` for the player, and
  is read again at each loading screen, so a ride that ends behind one can't leave the bar
  hidden. A party member's vehicle changes nothing. On a build without the vehicle events, chat
  says it could not register them, and the bar works without them.

### Moving the bar

Unlocked (untick Lock position, or `/grogue unlock`), the bar takes the mouse and shows a green
mover around it with "gRogue - drag to move" above it. A left-button drag moves it, kept on the
screen, and the drop saves its place. `/grogue lock`, or ticking Lock position, locks it again.

### Errors

Every event handler, script and command runs guarded: an error is printed in chat instead of
unwinding, since the client's error frame is off by default. Each distinct error prints once, in
full, up to the 50 kept; past them errors are only counted. gRogue has no command that lists
errors, so none is pointed to. A blocked or forbidden action that names gRogue is printed too.

## Settings

Every setting is in `ns.defaults` (`Core.lua`), with its default. Every change applies at once.
A number's range is its slider's, and a list's choices its dropdown's; a saved value outside them
goes back to its default at load ([Saved data](#saved-data)).

| Setting | Default | Range | |
| --- | --- | --- | --- |
| `locked` | true | | Lock position. Unlocked, the bar can be dragged. |
| `point` | `CENTER` | `TOPLEFT`, `TOP`, `TOPRIGHT`, `LEFT`, `CENTER`, `RIGHT`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT` | The bar's point that is placed. Set by the drag. |
| `relativePoint` | `CENTER` | `TOPLEFT`, `TOP`, `TOPRIGHT`, `LEFT`, `CENTER`, `RIGHT`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT` | The point of the screen it is placed from. Set by the drag. |
| `x` | 10.8 | | The offset from it, in the screen's units. Set by the drag. |
| `y` | -250.8 | | |
| `orientation` | `HORIZONTAL` | `HORIZONTAL`, `VERTICAL` | |
| `reverse` | false | | Reverse direction. |
| `pipWidth` | 50 | 4–100 | Point width. |
| `pipHeight` | 25 | 4–100 | Point height. |
| `spacing` | 4 | 0–30 | Between the points. |
| `scale` | 1 | 0.5–2 | The window shows it in percent, in steps of 5. |
| `alpha` | 1 | 0.1–1 | Opacity: the window shows it in percent, in steps of 5. |
| `texture` | `flat` | `flat`, `blizzard`, `raid` | |
| `smooth` | true | | Smooth fill, where the client has it. |
| `fillColor` | 1, 0.82, 0 | | Filled colour, for every point while `usePipColors` is off. |
| `emptyColor` | 0, 0, 0 | | |
| `emptyAlpha` | 0.35 | 0–1 | Empty opacity, in percent in the window, in steps of 5. |
| `border` | true | | Show border. |
| `borderSize` | 1 | 1–6 | |
| `borderColor` | 0, 0, 0 | | |
| `usePipColors` | true | | Colour each point separately. |
| `pipColors` | below | | Point 1 to Point 5. |
| `hideWithoutTarget` | true | | |
| `hideOutOfCombat` | true | | |

A colour is `{ r, g, b }`, each from 0 to 1. `pipColors` is a list of five, by default (1, 0.9,
0.2), (1, 0.75, 0.15), (1, 0.6, 0.1), (1, 0.4, 0.1) and (0.9, 0.15, 0.1).

## Commands

`/grogue`. The command is case-insensitive, and spaces around it are ignored. On a class other
than rogue, every command says "only active on rogues." and does nothing else.

| Command | |
| --- | --- |
| `/grogue`, `/grogue config` | Opens the settings, or closes them. |
| `/grogue unlock` | Unlocks the bar to drag it: "unlocked. Drag to move, then /grogue lock." |
| `/grogue lock` | Locks it: "locked." |
| `/grogue reset` | Puts every setting back to its default: "settings reset to defaults." |
| anything else | The usage: `/grogue [config \| unlock \| lock \| reset]`. |

The addon list on the minimap (the addon compartment) has gRogue too: a click is `/grogue`, and
hovering says a click opens the settings, or that gRogue is only active on rogues.

## Saved data

`WTF\Account\<account>\SavedVariables\gRogue.lua` holds `gRogueDB`, the settings for the whole
account: every setting by its key, with the defaults filled in for any that are missing, colours
as `{ r, g, b }` and `pipColors` as a list of five of them. A key this version doesn't know is
left alone.

The bar's place is `point`, `relativePoint`, `x` and `y`, from the screen (UIParent), in the
screen's units: the drop saves the offset the client answers times the bar's scale, and placing
divides by it, so the bar stays where it is when its scale changes.

At load, before anything reads it:

- A save that isn't a table gives way to the defaults, in a new table, and chat says the saved
  settings were unreadable.
- A saved value this version can't use goes back to its default, and chat names each: a value of
  the wrong type, past its range, off its list, a number that isn't finite, or a colour without
  numeric `r`, `g` and `b` each from 0 to 1. Each of the five point colours is checked on its own.
- A saved `false` is kept, not taken for a missing value.

## How the bar is built

- **The count goes to `StatusBar:SetValue` and nowhere else.** It is a secret for addon code, so
  nothing compares it, tests it, or does arithmetic with it, and no bar holding it is read back.
  Each point is a StatusBar ranging k-1 to k, so the client draws it empty below k and full at or
  above it, without the count being read.
- **Nothing is anchored to a bar holding the count but its clip frame.** The bars only receive
  the secret, and the only thing anchored to one is the clip frame, so their secret state never
  spreads into the rest of the layout: each point's background and border are on the point's own
  frame.
- **`SetValue`'s interpolation is looked up once, at load.** The argument can't be nil, so a
  member a build lacks would make every update raise; without both members `SetValue` gets the
  count alone.
- **Combat is the events, not `InCombatLockdown()`**, which is still false inside
  `PLAYER_REGEN_DISABLED` on this client.
- **Every handler, script and command is guarded**, the drag's included, through the kit's
  `ns.Guard`, and every event registered through the kit's `ns.On`: under `pcall`, since an event
  a build lacks throws on registration, and for the player alone where a unit is given.
- **A setting changes through `ns:Set`**, which does nothing for the value already set: a slider
  reports every pixel of a drag, most of them the same value. A reset empties `gRogueDB` in place,
  so everything holding it keeps the same table, and closes an open colour picker first, whose
  Cancel would otherwise write the old colour into the fresh defaults.

## UI design rules

The settings window is built from the kit's controls, gFrames' set, and follows gFrames' design
rules (gFrames' docs/SPEC.md, UI design rules): a standalone window in the flat, dark style, not a
page in Blizzard's settings, with gFrames' panel palette and the rogue's class yellow as its
accent, as gRogue's name is in chat. What is gRogue's own:

- A title bar, "gRogue" in the accent and "combo points" muted, with a close button at the
  right. The window can be dragged, and Escape closes it.
- Two columns. The first: Position (Lock position); Layout (Orientation, Reverse direction, Point
  width, Point height, Spacing, Scale, Opacity); Visibility (Hide without a target, Hide out of
  combat). The second: Style (Texture, Smooth fill where the client has it, Filled colour, Empty
  colour, Empty opacity, Show border, Border size, Border colour); Point colours (Colour each
  point separately, Point 1 to Point 5).
- A footer: "Unlock to drag the bar. Changes apply immediately." muted on the left, and "Reset
  all" on the right, which puts every setting back to its default.
- Every change applies at once; nothing waits for a `/reload`. A slider runs from end to end of
  its setting's range, a percent shown 0 to 100 and stored 0 to 1. A dropdown offers exactly its
  setting's list. A colour swatch opens Blizzard's colour picker, whose Cancel puts back the colour
  it opened on. Filling the window writes nothing back.

## Client facts

What gRogue relies on about the client. gFrames' docs/SPEC.md, Client facts, has the client
behaviour the addons share, and gkit's registry (`facts/forever-client-facts.md`) the facts every
addon relies on, by number.

- The combo point count, from `GetComboPoints` or `UnitPower`, is a secret for addon code
  (`GetComboPoints` is `SecretWhenUnitPowerRestricted` in the API docs; gkit CF-013).
- `GetComboPoints` is what Blizzard's own combo frame reads. `UnitPower` still reports the
  previous target's count when `PLAYER_TARGET_CHANGED` fires.
- Blizzard's own combo frame updates on every player power change, energy ticks included.
- `UnitInVehicle` has no secret return in Forever's API docs.
- `InCombatLockdown()` is false inside `PLAYER_REGEN_DISABLED` (gkit CF-074).
- `StatusBar:SetValue`'s second argument, the interpolation, can't be nil. Without it a bar
  snaps (`Immediate`, the client's default). The beta build has `ExponentialEaseOut` and
  `Immediate` (gkit CF-136).
- Registering an event the build doesn't have throws.
- The client's error frame is off by default (`/console scriptErrors 1` shows it).
- The client answers `GetPoint` with the anchor last set, so the drop reads the place the drag
  left (gkit CF-119).

## Decisions

These hold. Each says why, so it isn't undone by accident.

- **Every player power change reads the count, not only combo point changes.** The power token
  `UNIT_POWER_FREQUENT` carries for combo points is unverified on this client (gkit CF-059), and a
  wrong filter would stop the bar updating at all.
- **Smooth fill eases a gain and empties a spend at once.** The count can't be compared, so a
  gain can't be told from a spend to choose the interpolation; two bars a point, the smaller
  showing, give both.
- **`gRogueDB` stays gRogue's own.** The kit's Config only checks saved values; the save keeps
  every setting and leaves unknown keys alone.
- **Every kept error prints in full.** gRogue has no command that lists errors, so the kit's
  terse count line would point nowhere.

## Open questions

- The power token `UNIT_POWER_FREQUENT` carries when a combo point is built (gkit CF-059).
- `Enum.StatusBarInterpolation`'s members on the launch build (gkit CF-136). A renamed member
  takes smooth fill out of the window rather than breaking the bar.
