# Relic — CLAUDE.md

Relic is a personal life-map app: a single `index.html` (~4,800 lines), no
build step, no framework. Mapbox GL JS for the map, Supabase for
auth/storage/sync. There is no bundler — every edit lands directly in
`index.html`, so keep edits surgical (`str_replace`-style) rather than
rewriting whole sections.

Treat this file as a starting map, not gospel — if it disagrees with the
actual code, the code wins. Update this file when you add a new convention
future sessions would need.

## Architecture at a glance

- One `<script>` block (not a module, not strict mode). Top-level `function`
  declarations are hoisted and reachable, but the app *also* registers every
  function meant to be called from inline `onclick="..."` via a `_r(name, fn)`
  helper near the bottom of the script (`_fns` registry + `window[name]=fn`).
  **Always add a `_r()` entry for any new function used in an inline
  `onclick`** — it's cheap, consistent with the rest of the file, and the
  registry is a de facto manifest of the app's "public" functions.
- `db` is an in-memory object keyed by id, holding both **Moments** (tracked
  activities, pins, manual entries — anything that isn't a Story) and
  **Stories** (curated groups of Moments via `momentIds`). `isStory(obj)`
  distinguishes them.
- Persistence: `activities` and `stories` tables in Postgres via Supabase.
  `rowToMoment`/`momentToRow` and `rowToStory`/`storyToRow` are the single
  serialization choke points — any new Moment/Story field needs a matching
  column (see `docs/supabase-retrospective.sql` for the migration pattern)
  and an entry in both mapper functions.
- New Moments/Stories created anywhere in the app should follow the same
  save sequence as `doImport()`: mutate `db`, refresh `allMemories`/
  `allStories`, call `initMapLayers()` + `updateHeaderStats()` +
  `applyFilters()` (+`buildStats()` if the Archive view might be visible),
  then `await persistMoments(entries)` (or `sb.from('stories').upsert(...)`
  for a Story) — and roll back the local `db` entry if the persist fails.
- `TYPE_CONFIG` (tracked activity types: Run/Ride/Hike/.../Flight/Drive/Other)
  and colors in `relic_colors_v1` (localStorage) are for GPS-shaped Moments.
  Do not add pin categories into `TYPE_CONFIG` — see below.

## Data model — Retrospective entry (Pins, manual entry, NL parser, draw-route)

Added on the `retrospective-entry` branch. Goal: let a user build their life
map without live GPS tracking. Explicitly **out of scope** on this branch,
and still out of scope going forward until the app moves to a native/
Capacitor shell: live/background GPS tracking, tracking-interval selection,
charging-state detection, or any Capacitor work. If a future change starts
touching those, stop and flag it rather than extending what's here.

**Moment fields added:**
- `isPin` (bool) + `pinCategory` (string key into `PIN_CATEGORIES`) — a Pin
  is a point Moment with no polyline. `getMoments()` now excludes pins
  (`o.isPin`); `getPins()` returns only pins; `isPinMoment(o)` tests one
  object. Every existing distance/stats/feed/list consumer already goes
  through `getMoments()`, so pins are automatically excluded from all of
  them without further per-consumer changes — extend `getMoments()`'s filter,
  not each caller, if this needs to change again.
- `endLat`/`endLng`/`startPlace`/`endPlace` — a second labeled endpoint.
  Needed because nothing in the original schema names a Moment's destination
  (a Strava/GPX Flight Moment is just a polyline; the endpoint is only
  recoverable as "last coordinate," with no name). Manual entries, NL-parsed
  legs, and drawn routes all populate these where relevant.

**`PIN_CATEGORIES`** (near `TYPE_CONFIG`, ~line 1420) is a *separate* config
object — home/school/work/special/restaurant/nature/milestone/airport/other,
each with `label`/`color`/`icon` (a plain emoji, no icon library in this
codebase). Kept separate from `TYPE_CONFIG` because merging them would
corrupt `getGroup()`'s reverse lookup (`TYPE_GROUP_MAP`), which assumes every
key maps to GPS-shaped Strava type strings. Pin colors reuse the *same*
`relic_colors_v1` localStorage blob as tracked-type colors (it's just a flat
`{key: color}` map, and pin category keys don't collide with `TYPE_CONFIG`
keys) — see `loadColors()`. The Colors/Types settings panel
(`buildToolsPanel()`) has a third "Pins" tab driven by `PIN_CATEGORIES` and
`activePinCategories`.

**Pins render as DOM `mapboxgl.Marker` elements** (`renderPinMarkers()`), not
a GL symbol layer with an emoji `text-field`. Mapbox GL's text-field glyph
pipeline is server-rendered SDF fonts that typically don't cover emoji
pictograph ranges — an emoji `text-field` risks rendering as blank glyphs.
A DOM marker uses the browser's own emoji font, matching the pattern this
file already used for photo pins (`addPhotoMarker`). If pins ever need to be
GL-filterable/clustered at scale, that's the tradeoff to revisit.

**Manual entry** (`openManualEntryModal`/`saveManualEntry`) geocodes a start
(required) and optional end location via the shared `geocodeAddress()`
helper (Mapbox Geocoding v5). If an end location is given, it draws a
*straight* two-point line (`encodePolyline`) between start and end — this is
deliberately not a road-matched route (no GPS trace to snap to), just a
point-to-point line so the entry is visible on the map and contributes a
straight-line distance.

**NL route parser** (`parseRouteText` — pure, no DOM/network) detects a
flight-verb sentence vs. a default transport mode, strips the leading
verb/"from", and splits the remainder on `\bto\b` into an ordered waypoint
list. v1 scope: **one transport mode per sentence** — a sentence that
switches modes mid-trip ("drove to Denver, then flew to Seattle") is not
handled and is an explicit future stretch goal, not a bug to fix reflexively.
Each leg becomes its own Moment (`source:'nlparse'`); a chain of 2+ legs is
auto-grouped into a Story via the existing `momentIds` curation model. Flight
legs are resolved via `geocodeWaypoint(name, isFlight)` (tries `"<name>
airport"` against Mapbox Geocoding first; `IATA_FALLBACK` is a dozen major
airports as a documented fallback only) and rendered as a great-circle line
(`greatCircleCoords`) rather than a road-matched route. Non-flight multi-leg
chains use one Mapbox Directions call with all waypoints
(`fetchDirectionsMultiLeg`, `steps=true`), reconstructing each leg's geometry
by concatenating its steps' decoded polylines.

**Draw-your-route** (`openDrawRoutePicker`/`startDrawMode`/`addDrawPoint`/
`finishDrawRoute`) — pick foot/bike/car (Mapbox Directions profiles) or
manual (straight lines, no snapping) before tracing. Each new tapped point
calls Directions for a two-point segment snap (foot/bike/car) or is pushed
straight into the point list (manual); a live distance readout shows in the
`#mode-banner` UI. **v1 deliberately does not include** (add as new
functions/UI when picked up, don't retrofit into the existing ones): drag-to-
reposition an existing point, drag-a-segment-to-insert-a-point, undo/redo,
right-click/long-press context menus on points or segments, or an elevation
profile display.

**Airports view** (`switchView('airports')` → `buildAirportsView()`) is
computed on every view-open from `computeAirportVisits()` — it scans
`getMoments()` for `getGroup(type)==='Flight'`, reads each Moment's two
endpoints (falling back to the decoded polyline's last coordinate + "Unknown
airport" grouping for legacy Strava/GPX flights that predate `endLat`/
`endPlace`), and counts visits per airport. **There is no stored airports
table or counter** — do not add one; this must stay derived, or it will
drift from the underlying Moments (the reason the codebase avoids redundant
derived state everywhere else too).

**Long-press track preview** — right-click (`contextmenu`) on desktop,
touch-and-hold (~500ms, cancelled on move/release — `initLongPress()`) on
mobile, both hit-testing the `tracks-hit` layer. Opens a `mapboxgl.Popup`
(first use of Popup in this file) with name/stats/cover photo, reusing
already-computed fields — no new calculations. **Cover photo**: each photo
row in `activity_photos` has an `is_cover` boolean (not an array index —
survives reordering/deletion cleanly); `setCoverPhoto(memId, idx)` clears any
existing cover for that Moment and sets the new one. Toggled via a ★ button
on each photo thumbnail in the existing photo grid (`renderPhotos`).

**Shared helper**: `geocodeAddress(query)` (Mapbox Geocoding v5, one shared
fetch wrapper) is used by Pins, Manual Entry, and the NL parser — extend this
one function rather than adding a second geocoding call site.

**Entry point**: a single "+ Add" nav button (header + mobile menu) opens
`#add-modal`, a chooser between the five ways to add something without live
tracking (drop a pin / pin by address / manual entry / describe a trip /
draw a route), rather than cluttering the header with one button per
feature.

### Known follow-ups (not built here, deliberately deferred)

- Draw-route: drag-to-reposition points, drag-to-insert, undo/redo,
  point/segment context menus, elevation profile.
- NL parser: mixed-mode sentences ("drove to X, then flew to Y").
- Airports view: airports aren't rendered as map pins with a count badge
  (only listed in the Airports view itself) — a nice-to-have if it's ever
  wanted, not required by the current spec.
- Mobile bottom tab bar still shows only Map/Feed/Archive/Profile — Airports
  is reachable via the header nav and hamburger menu but wasn't added as a
  5th fixed-width tab, to avoid an unreviewed layout change to that bar.
- Pin-drop mode: clicking exactly on an existing pin marker while in pin-drop
  mode does nothing (the marker's own click handler absorbs the click before
  it reaches the map canvas) rather than dropping a new pin at that spot.
