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
| `--route-sage` | `#8FA888` | Route family (snow activities) |
| `--route-tan` | `#C9B896` | Route family (wheels and air) |
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

Ten activity types and three route colours, so each family comes in shades.
Users can still recolour any type (Filters → Track colours), and those
overrides win.

| Family | Types (default shade) |
|---|---|
| **Rust, on foot** | Run `#C1502E` · Hike `#9A3B22` · Walk `#D8785A` |
| **Sage, snow** | Alpine ski `#6F8B66` · Nordic ski `#8FA888` · Backcountry `#4F6A4A` |
| **Tan, wheels and air** | Ride `#B39A6A` · Drive `#8C7650` · Flight `#C9B896` · Other `#A89F8C` |

A selected track is drawn thicker with everything else dimmed.

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
