# Enemy Totem Marker (TBC) — Technical Overview

A World of Warcraft addon for **The Burning Crusade Classic (2.5.5, interface
`20505`)** that marks enemy totems on their nameplates with the totem's icon, a
lifetime/tick countdown, and an element-colored border.

This is the **TBC branch** — a separate port of the Mists of Pandaria Classic
version. The two share a concept and visual style but diverge in code because
TBC runs on an older engine (no modern Settings API, different totem data). See
[Differences from the MoP version](#differences-from-the-mop-version).

- Branch: `tbc`
- Version: **0.7.7b-tbc**
- TBC port by **Denlex92**
- Saved variables: `EnemyTotemMarkerDB`
- Slash commands: `/tm`, `/tm config`

---

## File layout

```
EnemyTotemMarker/
├── EnemyTotemMarker.toc   # addon manifest (interface 20505, SavedVariables)
├── EnemyTotemMarker.lua   # entire implementation (single file, ~333 lines)
├── icon.png               # project/branding asset (not shipped in the zip)
└── docs/
    └── project-overview.md
```

Single Lua file, no external libraries.

---

## Runtime environment notes (TBC Classic 2.5.x)

TBC Classic runs on an **older client engine** than MoP Classic, which drives
the main implementation differences:

- **No modern Settings API.** The options panel is registered with the legacy
  **`InterfaceOptions_AddCategory`** and opened with
  `InterfaceOptionsFrame_OpenToCategory` (called twice — a well-known Blizzard
  quirk where the first call only expands the tree).
- **Totem identity by name, not spell ID.** TBC totems are matched by their
  **localized creature name** against a static `TOTEM_DATA` table that stores the
  icon path directly. There is no `GetSpellInfo(spellID)` / `C_Spell` lookup.
- **Nameplates** still use `C_NamePlate.GetNamePlateForUnit` /
  `GetNamePlates` (present in 2.5.x), accessed through guarded wrappers
  (`GetNamePlate` / `GetNamePlates`).
- **Texture color** uses `SetColorTexture` when present, falling back to the old
  `SetTexture(r,g,b,a)` signature (`SetSolidColor` helper).
- On login the addon enables Blizzard's enemy-totem nameplates via
  `SetCVar("nameplateShowEnemyTotems", 1)` (guarded by `pcall`).

---

## Data model

### Totem table (`TOTEM_DATA`)

Keyed by **localized totem name**, each entry holds everything the marker needs:

```lua
["Grounding Totem"] = {
    icon     = "Interface\\Icons\\Spell_Nature_Groundingtotem",
    element  = "Air",          -- Fire | Earth | Water | Air (border color)
    duration = 45,             -- lifetime in seconds
    important= true,           -- enlarged icon (IMPORTANT_SCALE)
    timer    = "lifetime",     -- timer mode (see below)
}
```

The table covers the TBC shaman totem roster (Air / Earth / Fire / Water),
including Grace of Air, Windfury, Wrath of Air, Tremor, Earthbind, Stoneskin,
Searing, Fire Nova, Magma, Totem of Wrath, Healing Stream, Mana Spring, Mana
Tide, the resistance and cleansing totems, etc.

### Name normalization

`NormalizeName(name)` strips trailing rank numerals (`" II"`, `" III"`) and
parenthetical suffixes, so ranked totem names still resolve. `GetData(name)`
tries the exact name first, then the normalized form.

### Timer modes (`timer` field)

- `nil` / absent — no countdown text (icon + border only).
- `"lifetime"` — counts the totem's remaining lifetime; under 10s shows one
  decimal, otherwise whole seconds. Used for Grounding, Earthbind, Mana Tide,
  Fire Nova.
- `"tremor"` — shows the **time until the next tremor pulse**
  (`TREMOR_TICK - ((now - start) % TREMOR_TICK)`), not the lifetime. Used for
  Tremor Totem so you can time fear/charm/sleep breaks.

### Element colors

`ELEMENT_COLOR` maps element name → `{r, g, b}`; `COLOR_BLACK` is the fallback
border color for totems with no known element.

### SavedVariables schema (`EnemyTotemMarkerDB`)

```lua
EnemyTotemMarkerDB = {
    borderSize = 2,   -- global border thickness (0..BORDER_SIZE_MAX)
    fontSize   = 15,  -- global base timer font size (FONT_SIZE_MIN..MAX)
}
```

There is **no per-totem saved list** in the TBC port — the tracked totems are
the static `TOTEM_DATA` table, and important totems get a fixed
`IMPORTANT_SCALE`. Only the two global appearance settings are persisted.

---

## Config constants

| Constant | Value | Meaning |
|---|---|---|
| `MARKER_SIZE` | 32 | base icon size (px) before scale |
| `DEFAULT_SCALE` | 1.0 | scale for normal totems |
| `IMPORTANT_SCALE` | 1.5 | scale for `important` totems |
| `MARKER_Y_OFFSET` | 6 | gap above the nameplate (px) |
| `UPDATE_THROTTLE` | 0.05 | countdown refresh interval (s) |
| `TREMOR_TICK` | 3 | tremor pulse interval (s) |
| `BORDER_SIZE_MAX` | 6 | border thickness max |
| `FONT_SIZE_MIN` / `FONT_SIZE_MAX` | 6 / 30 | font size range |

---

## Marker lifecycle

Markers are pooled frames reused across totems.

1. **`AcquireMarker()`** — pulls from `markerPool` or builds a `Frame` (strata
   HIGH) with a `border` texture (BACKGROUND), an `icon` texture (ARTWORK,
   trimmed `SetTexCoord`), and a yellow `timer` FontString (OVERLAY); border and
   font are applied via `ApplyBorder` / `ApplyFont`.
2. **`ShowMarkerForUnit(unit)`** — guards via `IsEnemyTotem(unit)` (creature
   type == `TOTEM_TYPE` and attackable), finds the nameplate, looks up
   `GetData(UnitName(unit))`, sizes the marker (`MARKER_SIZE * scale`, where
   important totems use `IMPORTANT_SCALE`), stores `m.totemScale`, applies
   font/border/icon/element-color, parents to the nameplate and anchors
   `BOTTOM → nameplate TOP` with `MARKER_Y_OFFSET`. If the totem has a duration
   and timer mode it starts the `OnUpdate` countdown; first-seen time is cached
   per GUID in `startByGUID` so the timer survives marker recycling.
3. **`MarkerOnUpdate`** — throttled to `UPDATE_THROTTLE`; renders text per the
   timer mode; clears itself and frees the GUID at expiry.
4. **`HideMarkerForUnit` / `ReleaseMarker`** — clears scripts/text/mode/guid,
   hides, reparents to `UIParent`, returns to `markerPool`.

`RefreshAll()` rebuilds every marker from the current nameplates — used on
`PLAYER_ENTERING_WORLD`.

### Appearance helpers

- **`ApplyBorder(m)`** — re-anchors the border to `±db.borderSize`, hidden at 0.
  `RefreshBorders()` applies to all live + pooled markers.
- **`ApplyFont(m)`** — sets the timer font to `db.fontSize * m.totemScale`
  (rounded, min 1), so the **countdown scales with the icon**. `RefreshFonts()`
  applies to all markers.

---

## Options panel (legacy InterfaceOptions)

Registered with `InterfaceOptions_AddCategory`; opened via **ESC → Interface →
AddOns → EnemyTotemMarker** or `/tm config`. Minimal by design:

- A title and a one-line hint about which totems show which timer.
- **Border thickness** — `-` / `+` buttons (`db.borderSize`, clamped
  `0..BORDER_SIZE_MAX`), live `RefreshBorders()`.
- **Timer font size** — `-` / `+` buttons (`db.fontSize`, clamped
  `FONT_SIZE_MIN..MAX`), live `RefreshFonts()`.

There is no scrolling list / per-totem editor in the TBC port.

---

## Events

A single frame handles:

- **`PLAYER_LOGIN`** — initialize `EnemyTotemMarkerDB`, apply `DEFAULTS`,
  `SetupOptions()` (pcall), `RefreshBorders`, `RefreshFonts`, enable
  enemy-totem nameplates, print a load message.
- **`PLAYER_ENTERING_WORLD`** — `RefreshAll()`.
- **`NAME_PLATE_UNIT_ADDED`** — `ShowMarkerForUnit(unit)`.
- **`NAME_PLATE_UNIT_REMOVED`** — `HideMarkerForUnit(unit)`.

---

## Slash commands

- **`/tm`** — inspects the current target and prints `name`, normalized name,
  creature type, npc ID, whether it has data, and its timer mode. Useful for
  diagnosing totems that don't match `TOTEM_DATA`.
- **`/tm config`** — opens the options panel.

---

## Differences from the MoP version

| Area | MoP (`master`, 50504) | TBC (`tbc`, 20505) |
|---|---|---|
| Totem identity | spell ID + `GetSpellInfo` | localized name + static `TOTEM_DATA` (icons hardcoded) |
| Totem roster | MoP totems (Capacitor, Spirit Link, Healing Tide, Stormlash, …) | TBC totems (Grace of Air, Windfury, Tremor, Fire Nova, Totem of Wrath, …) |
| Options API | modern Settings canvas | legacy `InterfaceOptions_AddCategory` |
| Options scope | tracked-list editor, add/remove by ID, per-totem scale, live preview | global border + font only; fixed `IMPORTANT_SCALE` |
| Timer modes | lifetime countdown | lifetime **and** tremor-tick |
| SavedVariables | `borderSize`, `fontSize`, `spells[id].scale` | `borderSize`, `fontSize` |

The marker pool, border/font scaling, element coloring, nameplate anchoring and
event flow are shared in spirit between both branches.

---

## Version note

- **0.7.7b-tbc** — TBC Classic 2.5.5 port: name-based totem data with hardcoded
  icons, the TBC totem roster, tremor-tick timer mode, and a legacy
  InterfaceOptions panel. Ported by Denlex92 from the MoP version.
