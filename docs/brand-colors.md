# Relic brand colours

What's actually in the app as of 2026-09-19. The tokens live on `:root` at the
top of `index.html`'s `<style>`. If this doc and the code disagree, the code
wins; update this file.

Relic should feel like a keepsake (an old atlas, a travel journal), not a
fitness-tracker dashboard. It is explicitly **not** Strava orange, and not
the AllTrails/Gaia green-and-orange "outdoor gear" look. The original
design-system artifact (with cover and preview):
https://claude.ai/artifact/3ojmhe25HU1F6iY3GRMy1g

## Where each mode is used

Rust is the one colour that stays the same in both modes.

- **Light mode is the app:** every screen, including the map, plus lists,
  forms and, later, the printed photo book (v0.9). Dark backgrounds don't work
  on paper, so the book inherits light mode.
- **Dark (forest) mode is hero surfaces only:** the loading screen, the login
  brand panel, the Open Graph share image and the Discord banners.
- A dark live-map view is in the original spec but **not built**. Decided
  2026-09-19: keep the map light for now.

Don't pair a dark-mode background with light-mode text, or the reverse.

## Brand colours

| Token | Hex | Used for |
|---|---|---|
| `--brand-rust` (= `--accent`) | `#C1502E` | Logo mark, primary buttons, active states, kudos heart, links. 4.7:1 with white text. Never swap for another accent. |
| `--accent-strong` | `#9A3B22` | Rust text on light rust tints (chips, badges) |
| `--accent-soft` | `#F6E3D9` | Light rust tint behind chips, unread notifications, selected rows |
| `--route-sage` | `#8FA888` | Decorative route lines on hero art only |
| `--route-tan` (= `--warm`) | `#C9B896` | Decorative route lines on hero art only |
| `--accent-gold` | `#B8934A` | Decorative dots on hero art only |

## Light mode (the app)

| Token | Hex | Used for |
|---|---|---|
| `--bg` | `#F4F0E8` | Page background |
| `--surface` (= `--paper`) | `#FBF9F4` | Cards, panels, modals |
| `--surface-2` (= `--paper2`) | `#EDE6D5` | Input fills, hover states, deep background |
| `--paper3` | `#E3DAC5` | Pressed and inactive fills, segmented-control track |
| `--text` (= `--ink`) | `#2A3324` | Body text, dark buttons |
| `--text-2` | `#4B5944` | Secondary text |
| `--text-3` (= `--muted`) | `#5C6B54` | Tertiary text and captions (still AA on `--bg` and `--surface`) |
| `--line-faint` (= `--border`) | `#DCD3BF` | Hairlines and dividers |
| `--success` | `#3F6B3A` | Checks, "Public" badges |
| `--danger` | `#B3261E` | Destructive actions and errors |

Note: in the code, `--ink` means light-mode text (a legacy name). The
spec's dark-mode "ink" is `--ink-on-dark`.

## Dark mode (hero surfaces)

| Token | Hex | Used for |
|---|---|---|
| `--forest` | `#1A2318` | Background |
| `--forest-deep` | `#0F140D` | Gradient end |
| `--ink-on-dark` | `#F5F1E8` | Text |
| `--ink-on-dark-2` | `#B8C4B0` | Secondary text |
| (hairline) | `#3A4536` | Decorative route texture, at reduced opacity |

## Map: activity tracks

Tracks deliberately **don't** use the brand palette. Each activity type has
its own bright, distinct colour (Material 600 shades), because telling types
apart at a glance matters more on a map than matching the brand. Users can
recolour any type in Filters → Track colours, and saved colours win.

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

- Tracks are plain lines with no outline. A selected track is drawn thicker,
  with everything else dimmed.
- All ten stay distinct on the outdoors and satellite map styles (renders in
  `brand/track-colours-bright-*.png`). Hike, green on green terrain, is the
  weakest on outdoors.

## Map: pins

- Every pin category defaults to **white** (`#FFFFFF`). The emoji icon tells
  the categories apart. Users choose their own colour per category in
  Filters → Pins, and saved colours win.
- Pin markers have a white border and a faint dark ring, so white pins stay
  visible on light map tiles.

## Assets in these colours

- `icon.svg` (favicon), `apple-touch-icon.png`, `icon-512.png` (web app
  manifest), `og-image.jpg` (link previews)
- `brand/`: app icons (512, 1024, 1024 rounded) and Discord banners (server
  960×540, profile 680×240)

## Tried and rejected (2026-09-19)

So these don't come back by accident:

- **Tracks in rust/sage/tan families.** On the outdoors map, sage nearly
  vanished into the forest green and tan washed out, and ten types in three
  families were too hard to tell apart.
- **A dark outline under tracks.** It fixed the contrast but didn't look
  right.
- **Gold pins.** Replaced by white defaults that users can colour themselves.
- **A dark map view.** Parked for now rather than rejected.
