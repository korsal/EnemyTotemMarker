<p align="center">
  <img src="icon.png" width="128" alt="Enemy Totem Marker icon">
</p>

<h1 align="center">Enemy Totem Marker</h1>

<p align="center">
  Marks enemy totems on their nameplates with the totem's icon, a lifetime
  countdown, and an element-colored border.
</p>

<p align="center">
  <a href="https://www.curseforge.com/wow/addons/enemy-totem-marker">
    <img src="https://img.shields.io/curseforge/dt/1590902?logo=curseforge&label=CurseForge" alt="CurseForge downloads"></a>
  <a href="https://www.curseforge.com/wow/addons/enemy-totem-marker/files">
    <img src="https://img.shields.io/curseforge/v/1590902?logo=curseforge&label=version" alt="CurseForge version"></a>
  <img src="https://img.shields.io/curseforge/game-versions/1590902?label=game%20version" alt="Game version">
</p>

---

Never miss an enemy totem again. Enemy Totem Marker places the totem's icon
above every enemy totem's nameplate, with a lifetime countdown and an
element-colored border so you can tell at a glance what just dropped and how
long it lasts.

Built for **Mists of Pandaria Classic (5.5.4, interface `50504`)**.

## Features

- **Icon on the nameplate** — every enemy totem is marked with its real spell
  icon (or a generic totem icon for unknown ones).
- **Lifetime countdown** — known totems show a timer counting down their
  duration, so you know exactly when Grounding, Capacitor, Tremor, etc. expire.
- **Element-colored border** — the marker border is tinted by the totem's
  element (Fire / Earth / Water / Air), for instant recognition.
- **Per-totem icon size** — make the totems you care about (Capacitor,
  Grounding, Spirit Link…) bigger than the rest.
- **Scaling timer** — the countdown font scales together with the icon.
- **Fully configurable in-game** — a tracked-totem list you can edit yourself.

## Installation

- **CurseForge:** install via the [CurseForge page](https://www.curseforge.com/wow/addons/enemy-totem-marker)
  or your addon manager.
- **Manual:** download the latest release and extract the `EnemyTotemMarker`
  folder into `World of Warcraft/_classic_/Interface/AddOns/`.

## How to use

1. Install and log in — the addon enables the "show enemy totems" nameplate
   option automatically.
2. Enemy totems are now marked on their nameplates.
3. Open the options panel to customize: **ESC → Options → AddOns →
   Enemy Totem Marker**, or type `/tm config`.

## Options panel

- **Border thickness** — global border width (with +/- steppers).
- **Timer font size** — global countdown font size.
- **Tracked totem list** — every totem the addon recognizes.
  - **Add** a totem by its spell ID.
  - **Remove** a totem from the list.
  - **Icon scale** — per-totem size, with a live preview that mirrors the
    on-nameplate marker (border + scale + sample timer).

## Slash commands

| Command | Description |
|---|---|
| `/tm` | Inspect your current target and print its totem info (name, npc ID, whether it's recognized) — useful for finding spell IDs to add. |
| `/tm config` | Open the options panel. |

## Notes

- All enemy totems are marked. Totems in the tracked list also get their real
  icon, countdown, element border and custom scale; unrecognized totems still
  get a generic marker so you never miss one.
- Found a totem that isn't recognized? Target it, run `/tm` to read its info,
  then add its spell ID in the options panel.

## Documentation

A detailed technical overview of the architecture, data model, and marker
lifecycle is available in [docs/project-overview.md](docs/project-overview.md).

## Feedback

Bug reports and suggestions are welcome on the
[issue tracker](https://github.com/korsal/EnemyTotemMarker/issues) or in the
CurseForge comments.
