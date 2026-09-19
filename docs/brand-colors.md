# Relic brand colours

Relic should feel like a keepsake (an old atlas, a travel journal), not a
fitness-tracker dashboard. It is explicitly **not** Strava orange, and not
the AllTrails/Gaia green-and-orange "outdoor gear" look. Full design-system
artifact (with cover/preview): https://claude.ai/artifact/3ojmhe25HU1F6iY3GRMy1g

## Two modes, one brand

Rust is the one colour that stays the same in both modes. It's what ties them
together as one brand.

- **Light mode** is the app: data entry, lists, forms, the map (for now), and
  later the printed photo book (v0.9). Dark backgrounds don't work on paper,
  so the book inherits light mode.
- **Dark mode** is hero/marketing surfaces: the login brand panel, the loading
  screen, the Open Graph image, the Discord banners. A dark live-map view is
  part of the spec but deliberately **not built yet** (decided 2026-09-19:
  keep the map light for now).

## Palette

| Token (in `index.html` `:root`) | Hex | Use |
|---|---|---|
| `--brand-rust` (= `--accent`) | `#C1502E` | Logo mark, primary buttons/CTAs, selected route. Never swap for another accent in either mode. 4.7:1 with white text. |
| `--route-sage` | `#8FA888` | Decorative route lines on hero art (not map tracks) |
| `--route-tan` | `#C9B896` | Decorative route lines on hero art (not map tracks) |
| `--accent-gold` | `#B8934A` | Pins and story markers **only**, never lines |
| `--forest` / `--forest-deep` | `#1A2318` / `#0F140D` | Dark-mode background / gradient end |
| `--ink-on-dark` / `--ink-on-dark-2` | `#F5F1E8` / `#B8C4B0` | Text on dark surfaces |
| `--bg` | `#F4F0E8` | Light-mode page background |
| `--surface-2` / `--paper2` | `#EDE6D5` | Light-mode deep background, input fills |
| `--text` (= `--ink`) | `#2A3324` | Light-mode text |
| `--text-3` / `--muted` | `#5C6B54` | Light-mode secondary text (AA on `--bg` and `--surface`) |
| `--line-faint` (= `--border`) | `#DCD3BF` | Hairlines and dividers (light). Dark-mode equivalent `#3A4536` at reduced opacity. |

Don't pair a dark-mode background with light-mode text, or the reverse.

Note: in the codebase `--ink` means *light-mode text* (a legacy name). The
spec's dark-mode "ink" is `--ink-on-dark`.

## Activity-type colours (map tracks)

Decided 2026-09-19: tracks deliberately **don't** use the brand palette. Each
activity type gets its own bright, distinct colour (Material 600 shades),
because telling types apart at a glance is more fun and more useful than
matching the brand. (A rust/sage/tan family version was tried and rejected.)
Users can still recolour any type (Filters → Track colours), and those
overrides win.

| Type | Colour | Hex |
|---|---|---|
| Run | Red | `#E53935` |
| Ride | Blue | `#1E88E5` |
| Hike | Green | `#43A047` |
| Walk | Purple | `#8E24AA` |
| Alpine ski | Pink | `#D81B60` |
| Nordic ski | Cyan | `#00ACC1` |
| Backcountry | Indigo | `#3949AB` |
| Flight | Orange | `#FB8C00` |
| Drive | Blue-grey | `#546E7A` |
| Other | Brown | `#8D6E63` |

All ten stay distinct on outdoors and satellite tiles (renders in
`brand/track-colours-bright-*.png`). Hike (green on green terrain) and Drive
lean on the dark casing most. A selected track is drawn thicker with
everything else dimmed.

## Contrast on real map tiles (tested 2026-09-19)

The spec flagged that rust, sage and tan sit at similar lightness. Rendered on
real Mapbox tiles through the Static Images API:

- **Satellite** and **dark** tiles: all three read clearly.
- **Outdoors** (the default light style): sage almost vanished into the forest
  green, and tan washed out on pale ground.
- **Fix:** a dark casing (`#1A2318` at 45%, about 3 px wider) under every
  track. With it, all three stay distinct on outdoors, including where tracks
  overlap. It's applied on the live map (`tracks-casing` layer) and in every
  static map image (`pathOv()`).

Pairwise contrast between the three route colours is low (sage vs tan about
1.3:1), so never rely on colour alone to tell two overlapping tracks apart.
The casing, line width and selection state carry that job.
