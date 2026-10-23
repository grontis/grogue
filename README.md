# gRogue

A combo point display for WoW Forever: a bar of five points that fill as a rogue builds combo
points on the target. Its size, shape (a row or a column, either way round), colours, texture,
border and when it shows are settings, and it can be dragged anywhere. Rogues only.

It is written for client 1.60.1 (interface 16001), which hands addons the combo point count as
a secret value; the bar is built so it never needs to read it.

## Install

This folder is the addon. Put it in the client's AddOns folder as `gRogue`:

```
<WoW>\_classic_beta_\Interface\AddOns\gRogue
```

To work on it, link the folder instead of copying it, so an edit is live after `/reload`:

```powershell
New-Item -ItemType Junction -Path "<WoW>\_classic_beta_\Interface\AddOns\gRogue" -Target "<repo>"
```

A file added or removed needs a client restart, not a `/reload`.

## Commands

| Command | |
| --- | --- |
| `/grogue` | Open the settings, or close them. Also in the addon list on the minimap. |
| `/grogue unlock` | Unlock the bar to drag it. It shows three points while unlocked. |
| `/grogue lock` | Lock it where it is. |
| `/grogue reset` | Every setting back to its default. |

## Settings

The settings window has the bar's position lock, its layout (a row or a column, reversed or
not, the points' width and height, the spacing, its scale and opacity), when it shows (hidden
without a target, hidden out of combat; both on by default), and its style: the texture, a
smooth fill, the filled and empty colours, the border, and a colour for each point. Every change
applies at once.

The settings are for the whole account, saved in
`WTF\Account\<account>\SavedVariables\gRogue.lua`.

## More

- [CLAUDE.md](CLAUDE.md): working on gRogue: the rules, the smoke tests, the layout and the
  pitfalls.
- [docs/SPEC.md](docs/SPEC.md): everything gRogue does, every setting with its default and
  range, the saved data, how the bar is built and the client facts it relies on.
