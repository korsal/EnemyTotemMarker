<p align="center">
  <img src="icon.png" width="128" alt="Enemy Totem Marker icon">
</p>

<h1 align="center">Enemy Totem Marker — TBC Classic</h1>

<p align="center">
  Marks enemy totems on their nameplates with the totem's icon, an
  element-colored border, and timers on the totems that matter.
</p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/enemy-totem-marker">
    <img src="https://img.shields.io/curseforge/dt/1590902?logo=curseforge&label=CurseForge" alt="CurseForge downloads"></a>
  <a href="https://www.curseforge.com/wow/addons/enemy-totem-marker/files">
    <img src="https://img.shields.io/curseforge/v/1590902?logo=curseforge&label=version" alt="CurseForge version"></a>
  <img src="https://img.shields.io/curseforge/game-versions/1590902?label=game%20version" alt="Game version">
</p>

---

Enemy Totem Marker places the totem's icon above every enemy totem's nameplate,
with an element-colored border and a countdown on the totems that matter most in
PvP, so you can react to Tremor, Grounding, Earthbind and more at a glance.

This is the **TBC build**, for **The Burning Crusade Classic (2.5.5, interface
`20505`)**. The Mists of Pandaria Classic build lives on the same CurseForge
project (and the `master` branch).

## Features

- **Icon on the nameplate** — every enemy totem is marked with its icon (or a
  generic totem icon for unknown ones).
- **Element-colored border** — tinted by the totem's element:
  - 🔴 **Fire** — orange-red
  - 🟤 **Earth** — brown
  - 🔵 **Water** — blue
  - 🩵 **Air** — cyan
- **Enlarged important totems** — key PvP totems (Grounding, Tremor, Earthbind,
  Mana Tide, Fire Nova, Healing Stream, elementals…) get a bigger icon.
- **Timers on the totems that matter** — only the critical ones, to avoid
  clutter:

  | Totem | Timer |
  |---|---|
  | Tremor Totem | Tick timer (3s pulse cycle) |
  | Earthbind Totem | Lifetime (45s) |
  | Grounding Totem | Lifetime (45s) |
  | Mana Tide Totem | Lifetime (12s) |
  | Fire Nova Totem | Lifetime (5s) |
  | All others | Icon only, no timer |

- **Scaling timer** — the countdown font scales together with the icon.
- **No spell-ID dependency** — totems are matched by unit name with hardcoded
  icons, so it doesn't rely on `GetSpellInfo`.

## Installation

- **CurseForge:** install via the [CurseForge page](https://www.curseforge.com/wow/addons/enemy-totem-marker)
  or your addon manager (the TBC client gets the TBC file automatically).
- **Manual:** download the latest TBC release, extract the `EnemyTotemMarker`
  folder into `World of Warcraft/_classic_/Interface/AddOns/`, then restart the
  game or `/reload`.

## How to use

1. Install and log in — the addon enables the "show enemy totems" nameplate
   option automatically.
2. Enemy totems are now marked on their nameplates.
3. Open the options panel to customize: **ESC → Interface → AddOns →
   EnemyTotemMarker**, or type `/tm config`.

## Options

- **Border thickness** — global border width.
- **Timer font size** — global countdown font size.

## Slash commands

| Command | Description |
|---|---|
| `/tm` | Inspect your current target and print its totem info (name, npc ID, whether it's recognized) — handy for debugging a missing/wrong icon. |
| `/tm config` | Open the options panel. |

### Fixing a missing or wrong icon

If a totem shows the wrong or a generic icon:

1. Target the totem.
2. Run `/tm`.
3. Copy the printed line — it contains the exact unit name the client returns,
   which can be added to the totem table.

## Supported totems

- **Air** — Grace of Air, Tranquil Air, Windwall, Windfury, Wrath of Air,
  Grounding, Nature Resistance.
- **Earth** — Tremor, Earthbind, Stoneskin, Stoneclaw, Strength of Earth,
  Earth Elemental, Totem of Wrath.
- **Fire** — Searing, Fire Nova, Magma, Flametongue, Fire Elemental,
  Frost Resistance.
- **Water** — Healing Stream, Mana Spring, Mana Tide, Disease Cleansing,
  Poison Cleansing, Fire Resistance, Cleansing.

## Notes

- A totem's timer starts from when it first appears on a nameplate. If the totem
  was already down before you came into range, the remaining time may read high.
- Tremor Totem shows only the tick timer (no lifetime countdown).

## Documentation

A detailed technical overview of the architecture, totem data model, and marker
lifecycle is available in [docs/project-overview.md](docs/project-overview.md).

## Credits

- Original idea and MoP Classic base: **reisal** —
  [Enemy Totem Marker](https://github.com/korsal/EnemyTotemMarker).
- TBC Classic 2.5.5 port (hardcoded icons, Tremor tick timer): **Denlex92**.

## Feedback

Bug reports and suggestions are welcome on the
[issue tracker](https://github.com/korsal/EnemyTotemMarker/issues) or in the
CurseForge comments.
