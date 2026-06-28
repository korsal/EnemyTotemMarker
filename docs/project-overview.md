# Enemy Totem Marker — Technical Overview

A World of Warcraft addon for **Mists of Pandaria Classic (5.5.4, interface
`50504`)** that marks enemy totems on their nameplates with the totem's icon, a
lifetime countdown, and an element-colored border. Totems and their appearance
are configurable in-game through an options panel.

- Current version: **0.7.0**
- Saved variables: `EnemyTotemMarkerDB`
- Slash commands: `/tm`, `/tm config`

---

## File layout

```
EnemyTotemMarker/
├── EnemyTotemMarker.toc   # addon manifest (interface 50504, SavedVariables)
├── EnemyTotemMarker.lua   # entire implementation (single file)
└── docs/
    └── project-overview.md
```

The addon is intentionally a single Lua file with no external libraries (no
Ace3), so it stays small and dependency-free.

---

## Runtime environment notes (MoP Classic)

MoP Classic runs on the **modern client engine** with MoP-era gameplay, which
mixes modern and legacy APIs. Relevant choices in this addon:

- **`GetSpellInfo`** is used as a **global with multi-return** (`name, rank,
  icon, ...`), not the retail `C_Spell.*` table form.
- **`FontString:SetFont`** is called with the flag string `"OUTLINE"`; invalid
  flag values (`"NORMAL"`, `"NONE"`, `false`) are rejected by the modern engine,
  so only valid flags are passed.
- **Texture color** uses `SetColorTexture` when present, falling back to the old
  `SetTexture(r,g,b,a)` signature (`SetSolidColor` helper).
- **Options UI** uses the modern **Settings canvas API**
  (`Settings.RegisterCanvasLayoutCategory` / `RegisterAddOnCategory`), with the
  registration wrapped in `pcall` so an API mismatch cannot break addon load.
- **Nameplates** are accessed through `C_NamePlate.GetNamePlateForUnit` and
  `C_NamePlate.GetNamePlates`.
- On login the addon enables Blizzard's enemy-totem nameplates via
  `SetCVar("nameplateShowEnemyTotems", 1)` (guarded by `pcall`).

---

## Data model

### SavedVariables schema (`EnemyTotemMarkerDB`)

```lua
EnemyTotemMarkerDB = {
    borderSize = 2,        -- global border thickness in pixels (0..BORDER_SIZE_MAX)
    fontSize   = 15,       -- global base timer font size (FONT_SIZE_MIN..MAX)
    spells = {             -- the user-managed tracked-totem list
        [spellID] = { scale = 1.5 },  -- per-totem icon scale multiplier
        ...
    },
}
```

`db.spells` is **seeded once** from the built-in `TOTEM_DB` on first login
(important PvP totems get `IMPORTANT_SCALE = 1.5`, the rest `DEFAULT_SCALE =
1.0`). After seeding it is fully user-controlled via the options panel — the
seed never runs again, so removed totems stay removed.

### Built-in reference tables (in code, not saved)

- `TOTEM_DB` — `spellID -> lifetime (seconds)`. Supplies the countdown duration
  for known totems.
- `TOTEM_ELEMENT` — `spellID -> "Fire" | "Earth" | "Water" | "Air"`. Drives the
  border color.
- `ELEMENT_COLOR` — element name -> `{r, g, b}`. `DEFAULT_BORDER_COLOR` (black)
  is used for totems with no known element.
- `IMPORTANT_PVP` — `spellID -> true`. Only used to seed default scales.
- `TOTEM_TYPE_BY_LOCALE` / `TOTEM_TYPE` — the localized creature-type string for
  "Totem", used to detect totems by `UnitCreatureType`.

### Derived name lookups (rebuilt by `BuildTotemDB`)

Markers are matched against the **localized creature name** (which equals the
totem's spell name), so `BuildTotemDB()` resolves `db.spells` into name-keyed
tables:

- `iconByName[name]` — spell icon texture.
- `durByName[name]`  — lifetime seconds (from `TOTEM_DB`, may be nil).
- `scaleByName[name]` — per-totem icon scale.
- `colorByName[name]` — element border color (from `TOTEM_ELEMENT`).

`BuildTotemDB` is re-run on every list edit (add / remove / scale change).

---

## Config constants

| Constant | Value | Meaning |
|---|---|---|
| `MARKER_SIZE` | 32 | base icon size (px) before per-totem scale |
| `DEFAULT_SCALE` | 1.0 | scale for a newly added / unconfigured totem |
| `IMPORTANT_SCALE` | 1.5 | seed scale for important PvP totems |
| `SCALE_MIN` / `SCALE_MAX` | 0.5 / 3.0 | icon scale slider range |
| `MARKER_Y_OFFSET` | 6 | gap above the nameplate (px) |
| `UPDATE_THROTTLE` | 0.1 | countdown refresh interval (s) |
| `BORDER_SIZE_MAX` | 6 | border thickness slider max |
| `FONT_SIZE_MIN` / `FONT_SIZE_MAX` | 6 / 30 | font size slider range |
| `GENERIC_TOTEM_ICON` | spell_nature_manaregentotem | fallback icon |

---

## Marker lifecycle

Markers are pooled frames reused across totems.

1. **`AcquireMarker()`** — pulls a frame from `markerPool` or builds one:
   `Frame` (strata HIGH) with a `border` texture (BACKGROUND), an `icon`
   texture (ARTWORK, trimmed `SetTexCoord`), a `Cooldown` frame
   (`CooldownFrameTemplate`, numbers hidden, `noCooldownCount` so OmniCC skips
   it), and a `timer` FontString (OVERLAY, yellow). Border and font are applied
   via `ApplyBorder` / `ApplyFont`.
2. **`ShowMarkerForUnit(unit)`** — guards via `GetTotemName(unit)` (creature
   type == `TOTEM_TYPE` and attackable), finds the nameplate with
   `C_NamePlate.GetNamePlateForUnit`, sizes the marker (`MARKER_SIZE * scale`),
   stores `marker.totemScale`, applies font/border/color/icon, parents to the
   nameplate and anchors `BOTTOM → nameplate TOP` with `MARKER_Y_OFFSET`. If the
   totem has a known duration it starts a cooldown swipe and an `OnUpdate`
   countdown; the first-seen time is cached per GUID in `startByGUID` so the
   timer survives the marker being recycled.
3. **`MarkerOnUpdate`** — throttled to `UPDATE_THROTTLE`; shows one decimal
   under 10s, whole seconds above; clears itself at expiry.
4. **`HideMarkerForUnit` / `ReleaseMarker`** — clears scripts/text/cooldown,
   hides, reparents to `UIParent`, returns to `markerPool`.

`RefreshAll()` tears down all active markers and re-shows every current
nameplate — used after config edits and on `PLAYER_ENTERING_WORLD`.

### Appearance helpers

- **`ApplyBorder(marker)`** — re-anchors the border texture to `±db.borderSize`
  and hides it when thickness is 0. `RefreshBorders()` applies to all live +
  pooled markers.
- **`ApplyFont(marker)`** — sets the timer font to `db.fontSize *
  marker.totemScale` (rounded, min 1), so the **countdown scales with the
  icon**. `RefreshFonts()` applies to all markers.

---

## Options panel

Registered with the modern Settings canvas API; opened via **ESC → Options →
AddOns → Enemy Totem Marker** or `/tm config` (`Settings.OpenToCategory`).

Layout (top to bottom):

1. **Border thickness** slider (global, `db.borderSize`) with `± ` stepper
   buttons.
2. **Timer font size** slider (global, `db.fontSize`) with steppers.
3. **Add totem by spell ID** — numeric `InputBox` + `Add` button
   (`AddSpellByID`, validates via `GetSpellInfo`).
4. **Tracked totem list** — a `FauxScrollFrameTemplate` list. Row buttons are
   children of the panel (not the scroll frame) and anchored to it; the scroll
   frame only drives the scrollbar + offset. Mouse-wheel scrolling supported.
5. **Detail pane** (right) for the selected totem:
   - A **live preview** icon in a fixed slot, decorated to mirror the marker:
     element-colored border at the configured thickness, per-totem scale, and a
     sample countdown number whose font scales like the real timer (corrected by
     `PREVIEW_BASE / MARKER_SIZE`).
   - **Icon scale** slider (per-totem, `SetSpellScale`) with steppers.
   - **Remove totem** button (`RemoveSpellByID`).

Helper functions: `GetSortedSpellList()` (name-sorted snapshot of `db.spells`),
`AddSpellByID`, `RemoveSpellByID`, `SetSpellScale`. All mutate `db.spells` then
call `BuildTotemDB()` + `RefreshAll()`. `MakeStepper` builds the `±` arrow
buttons (page-turn arrow textures) since `OptionsSliderTemplate` has none.

---

## Events

A single frame handles:

- **`PLAYER_LOGIN`** — initialize `EnemyTotemMarkerDB`, apply `DEFAULTS`, seed
  `db.spells` once, `BuildTotemDB()`, `SetupOptions()` (pcall), `RefreshBorders`,
  `RefreshFonts`, enable enemy-totem nameplates, print a load message.
- **`PLAYER_ENTERING_WORLD`** — `RefreshAll()`.
- **`NAME_PLATE_UNIT_ADDED`** — `ShowMarkerForUnit(unit)`.
- **`NAME_PLATE_UNIT_REMOVED`** — `HideMarkerForUnit(unit)`.

---

## Slash commands

- **`/tm`** — inspects the current target and prints `name`, creature type,
  npc ID, attackability, and whether it's recognized. Used to discover spell IDs
  for the tracked list.
- **`/tm config`** — opens the options panel.

---

## Behavior notes / decisions

- **All enemy totems are marked.** The tracked list customizes recognized
  totems (real icon, countdown, element border, scale); unrecognized totems
  still get a generic marker so none are missed. Removing a totem from the list
  downgrades it to the generic look rather than hiding it.
- **Player detection / typos.** Spell IDs are validated on add; an unknown ID is
  rejected with a chat message.
- **Distribution packaging.** The release `.zip` contains only the
  `EnemyTotemMarker/` folder with `.toc` + `.lua`; `.git`, `.gitattributes`, the
  `docs/` folder, and the CurseForge avatar are excluded.

---

## Version history

- **0.7.0** — Options panel with editable tracked-totem list (add/remove by
  spell ID), per-totem icon scale, timer font that scales with the icon, global
  border thickness + timer font size sliders with stepper arrows, live preview;
  fixed Windwalk Totem id `114051` (was Ascendance) → `108273`.
- **0.6.0** — First options panel + SavedVariables (border thickness).
- **0.5.0** — Element-colored borders; added Magma Totem.
- **0.4.0** — Initial working version (icon + countdown markers).
