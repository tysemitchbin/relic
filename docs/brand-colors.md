# Relic brand colours

What's actually in the app as of 2026-09-20. The tokens live on `:root` at the
top of `index.html`'s `<style>`; the track colours live in
`activity-types.js`. If this doc and the code disagree, the code wins; update
this file.

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
its own bright colour, because telling types apart at a glance matters more
on a map than matching the brand. Users can recolour any type in Filters →
Track colours, and saved colours win (`relic_colors_v1` in localStorage, the
same blob pin colours use).

Defined in `activity-types.js` (shared by the app and the bulk importer).
Types only show in the filters if the user has at least one track of them.

A hue is **deliberately reused** by two activities that never sit side by
side, in a clearly different shade (user's call, 2026-09-20: bright colours,
reuse is fine when confusion isn't). Add a new type by taking another shade
in an existing family rather than inventing a 22nd hue.

| Type | Colour | Hex | Family |
|---|---|---|---|
| Run | Bright red | `#FF3D3D` | red |
| Motorbike | Dark red | `#D50000` | red |
| Road bike | Blue | `#2196F3` | blue |
| Swim | Azure | `#00A3FF` | blue |
| Boat | Navy | `#0D47A1` | blue |
| Mountain bike | Bright green | `#00C853` | green |
| Hike | Forest green | `#1B8A3F` | green |
| Alpine ski | Bright pink | `#FF2D87` | pink |
| Snowboard | Soft pink | `#FF80AB` | pink |
| Walk | Purple | `#AA47BC` | purple |
| Wheelchair | Violet | `#6A3FD1` | purple |
| Paddling | Teal | `#00BFA5` | teal/cyan |
| Surf & sail | Aqua | `#26E0D6` | teal/cyan |
| Nordic ski | Cyan | `#00BCD4` | teal/cyan |
| Gravel | Lime | `#C6D22E` | — |
| Backcountry | Indigo | `#3F51B5` | — |
| Skate | Yellow | `#FFD600` | — |
| Flight | Orange | `#FF9100` | — |
| Rail | Magenta | `#E040FB` | — |
| Drive | Blue-grey | `#546E7A` | — |
| Other | Grey | `#9E9E9E` | — |

- Tracks are plain lines with no outline. A selected track is drawn thicker,
  with everything else dimmed.
- The ten colours that predate the 2026-09-20 palette were checked on the
  outdoors and satellite map styles (renders in
  `brand/track-colours-bright-*.png`, now one palette out of date). Green on
  green terrain is the weakest case, which is why Hike went darker and
  Mountain Bike brighter.

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
- `brand/track-colours-*.png` are map renders used to compare track palettes.
  **They show the pre-2026-09-20 colours** — regenerate them next time the
  map is open on both map styles.

## Tried and rejected

So these don't come back by accident:

- **One unique hue per activity type** (the Material 600 set, 2026-09-19).
  It worked for ten types, but the travel modes and the Strava sport split
  took it to 21, and the extra hues landed too close together — Rail's brown
  sat right next to Other's. Replaced 2026-09-20 by reusing hues across
  activities that never appear side by side.
- **Tracks in rust/sage/tan families** (2026-09-19). On the outdoors map, sage nearly
  vanished into the forest green and tan washed out, and ten types in three
  families were too hard to tell apart.
- **A dark outline under tracks.** It fixed the contrast but didn't look
  right.
- **Gold pins.** Replaced by white defaults that users can colour themselves.
- **A dark map view.** Parked for now rather than rejected.
