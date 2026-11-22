# Seek — Brand & Icon Guidelines

## Concept: Aperture Lock
Two opposing `45°`-chamfered architectural viewfinder brackets locking onto a floating **Steel Sapphire** focal diamond in negative space. Built on a `256 × 256` geometric grid with `30+`-unit negative-space moats, optically thinned dark-surface geometry, and a dedicated `16–18 px` small-size cut for the macOS Menu Bar. Designed as the visual sibling to **Glance** (*Focal Frame*).

## Master Files (`Assets/LogoKit/`)
- **Symbol (Light UI):** `seek-symbol-color.svg`
- **Symbol (Dark UI / HUD):** `seek-symbol-on-dark.svg`
- **Small Cut (`≤ 24 px` / Menu Bar):** `seek-symbol-small.svg`, `MenuBarTemplate.png`, `MenuBarTemplate@2x.png`
- **Lockups:** `seek-horizontal-color.svg`, `seek-horizontal-on-dark.svg`, `seek-stacked-color.svg`
- **macOS App Icon:** `seek-app-icon-tile.svg`, `AppIcon.icns`
- **One-Colour & Web Exports:** `exports/` (`black`, `white`, `mono-4b83db`, `square`, `favicon.ico`, `site.webmanifest`)

## Colour Palette
| Role | Light Surfaces | Dark Surfaces / HUD |
|---|---|---|
| Viewfinder Brackets | `#12151C` (Deep Obsidian) | `#DCE6F5` (Platinum Ice) |
| Focal Diamond (Accent) | `#4B83DB` (Cobalt Sapphire) | `#7DA8ED` (Steel Sapphire) |
| App Tile Surface | — | `#0E1117` (Obsidian Titanium) |

## Clear Space & Minimum Size
- **Clear space:** Maintain at least `24 px` (on the `256` grid) around the mark on all sides.
- **Minimum size:** `16 px` digital (use `seek-symbol-small.svg` / `MenuBarTemplate`), `32 px` for horizontal lockups (`seek-horizontal-*`).

## Misuse to Avoid
- Do not rotate the mark away from `0°` or place a magnifying-glass handle onto the brackets.
- Do not use `seek-symbol-color.svg` (`#12151C`) on dark surfaces; always use `seek-symbol-on-dark.svg` or `exports/seek-symbol-color-white.svg`.
