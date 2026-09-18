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

## Filters + Activities view (merged from `map-filters`, 2026-09-04)

`retrospective-entry` originally branched off `main` *before* the separate
`map-filters` branch (persistent map prefs, a richer filter model, an
Activities table view) existed, so for most of this branch's life it only
had the old, simpler search/type-toggle/sort filtering. The user asked for
`map-filters`' work back partway through — it was merged in (`git merge
map-filters`), replacing the old system. If you're looking for
`activeTypes`/`activeYears`/`buildToolsPanel()`/`switchToolsTab()`/
`toggleType()` from an older version of this file, **they're gone** — not a
bug, this is what replaced them:

- **One `filters` object** (`defaultFilters()`) drives everything: the map
  tracks, the map sidebar list, and the Activities view, all via one
  predicate, `matchMoment(m, filters)`. Extend `matchMoment` (and
  `defaultFilters`) for a new filterable field, not a second predicate.
- **`buildFilterDrawer()`** replaces `buildToolsPanel()` — one collapsible-
  section drawer (`#filter-drawer`, opened via `openFilterDrawer()`/the ⚑
  toolbar button) covering type/source/date/distance/duration/elevation/
  heart-rate/mood/attributes, **plus a "Pins" section** (added during the
  merge) driven by `PIN_CATEGORIES`/`activePinCategories` — kept structurally
  separate from `filters` since Pins aren't tracked Moments and none of the
  distance/duration/HR-style filters apply to them. Track colors moved into
  this same drawer too ("Track colours" section, still `updateTypeColor()`).
- **Activities view** (`#activities-view`, `renderActivitiesView()`) is a
  sortable table reachable from the header nav, sharing `filteredMemories`
  with the map. The old Archive/stats page (`buildStats()`, `#stats-view`)
  is **parked** — code kept, not reachable from nav — per `map-filters`'
  original design, not something this merge changed.
- **Map prefs persist per-user** (`relic_mapprefs_v1_<uid>`): `filters`,
  `sidebarSort`, `terrainOn`, `satelliteOn`, and last camera position, via
  `saveMapPrefs()` (debounced) / `loadMapPrefs()` / `applyStoredFilters()`
  restored before the first render. `relic_colors_v1` stayed a separate key
  (a planned fold-in never actually shipped in `map-filters` before the
  merge) — `loadColors()` still reads it directly, unchanged.
- **`?demo` mode** (`DEMO` flag — `main` on `localhost`/no host + `?demo` in
  the URL) boots from synthetic in-memory data via a lightweight
  `makeStubMap()` instead of a real `mapboxgl.Map`, for offline testing
  without Mapbox tiles/tokens. **The stub does not fully support
  `mapboxgl.Marker`** (missing internal methods like `_addMarker`, beyond
  the documented API) — it predates Pins/draw-route/the NL-parser preview
  map, none of which existed when it was written. `renderPinMarkers()` and
  `renderDrawMarkers()` wrap their marker creation in try/catch so this
  degrades to "no visible pin/waypoint markers in demo mode" rather than
  crashing the whole render chain — don't remove those try/catches thinking
  they're dead code; they're load-bearing specifically for `?demo`. Real
  usage always has a genuine `mapboxgl.Map`, so this never affects real
  users. If `?demo` ever needs to visually exercise pins, the fix is
  extending `makeStubMap()` (or giving Marker creation its own demo-mode
  branch), not removing the try/catch.

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
object — restaurant, cafe_bar, accommodation, shop, nature, camping,
mountain, home ("Home (Past or Present)"), school, job, special, other, and
airport, each with `label`/`color`/`icon` (a plain emoji, no icon library in
this codebase). `airport` is auto-managed (see below) and deliberately
excluded from the manual "add a pin" category picker (`openPinModal`'s
`<select>` filters it out) — every other key is user-selectable. This exact
list came from the user directly (2026-09-04); don't add categories back in
speculatively (e.g. a prior draft had "milestone" — it's gone, not an
oversight) or rename existing ones without asking, since these are their
words for their own categories, not a generic taxonomy. Kept separate from
`TYPE_CONFIG` because merging them would
corrupt `getGroup()`'s reverse lookup (`TYPE_GROUP_MAP`), which assumes every
key maps to GPS-shaped Strava type strings. Pin colors reuse the *same*
`relic_colors_v1` localStorage blob as tracked-type colors (it's just a flat
`{key: color}` map, and pin category keys don't collide with `TYPE_CONFIG`
keys) — see `loadColors()`. Pin category toggles/colors are their own "Pins"
section inside `buildFilterDrawer()` (the `map-filters` branch's filter
drawer, merged into this branch 2026-09-04 — see "Filters + Activities view"
below), driven by `PIN_CATEGORIES` and `activePinCategories`; NOT part of
the `filters`/`matchMoment()` object, since distance/duration/HR-style
filtering makes no sense for a point Pin.

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
legs are resolved via `geocodeWaypoint(name, isFlight)` — **known IATA codes
resolve from the static `IATA_FALLBACK` table first**, not Mapbox Geocoding:
bare 3-letter codes ("LAX airport") were confirmed (not just suspected) to
geocode unreliably against Mapbox's general text search — resolve to an
unrelated place entirely — so geocoding is only the primary path for a full
airport name/city, with the table as the precise path for the dozen major
airports it covers. Flight legs render as a great-circle line
(`greatCircleCoords`) rather than a road-matched route. Non-flight multi-leg
chains use one Mapbox Directions call with all waypoints
(`fetchDirectionsMultiLeg`, `steps=true`), reconstructing each leg's geometry
by concatenating its steps' decoded polylines.

Clicking "Preview" (`previewParsedRoute`) geocodes + builds the route via the
shared `buildParsedRoute(text, dateVal)` (also used by Save), then opens
`#route-preview-modal` — a small standalone `mapboxgl.Map` instance
(`_routePreviewMap`) showing a draggable marker per waypoint, plus a wide
invisible `preview-route-hit` line layer over the route itself. Dragging a
marker mutates that waypoint's `{lat,lng}` in place and calls
`recomputeLegsAt(idx)` (→ shared `recomputePreviewLeg`), which re-snaps only
the leg(s) touching it — not the whole chain. **Clicking anywhere on the
route line itself** (not just an existing marker) calls
`insertPreviewWaypoint(legIndex, lngLat)`: splits that leg into two around a
new synthetic waypoint (`name:'Via point'`, spliced into `geocoded` right
before the leg's original endpoint so save-time leg naming stays correct),
recomputes both halves, and does a full marker/line rebuild
(`renderRoutePreviewMap(false)` — the `false` skips re-fitting the camera
bounds, which would otherwise jump around distractingly on every edit). This
is what makes the *whole* route draggable, not just its two/N named ends —
added after a user found endpoint-only dragging insufficient to fix a bad
road-snap. `Save` (`saveParsedRoute`) reuses the already-built
`_pendingParsedRoute` (so any drag/insert adjustment is preserved) if its
cache key (text+date) still matches the form, otherwise rebuilds fresh via
`buildParsedRoute`.

**Draw-your-route** (`openDrawRoutePicker`/`startDrawMode`/`addDrawPoint`/
`finishDrawRoute`) — pick foot/bike/car (Mapbox Directions profiles) or
manual (straight lines, no snapping) before tracing. Every control point
gets a **visible, draggable `mapboxgl.Marker`** (`renderDrawMarkers` — a
*full* rebuild of the marker set on every waypoint-array change, not an
incremental patch, since inserting a point mid-route shifts every index
after it and a stale per-marker closure over an old index would drag/re-snap
the wrong leg). The app originally drew a live line with no markers at all,
which made a bad road-snap impossible to see or fix; this was reworked after
live testing showed it. **Clicking anywhere on the drawn line** (hit-tested
against the `draw-route-hit` layer inside the single generic map click
handler in `initMap` — deliberately one handler with a hit-test branch, not
a second `map.on('click','draw-route-hit',…)` listener, so an insert-click
can't also fire as an append-click) calls `insertDrawWaypoint(legIndex,
lngLat)`, same split-the-leg-in-two approach as the preview map above (not a
coincidence — this and the preview map's insert are the same pattern
independently applied to two different Mapbox instances; copy it again for
a third "drag a route" UI rather than reinventing it). State is
`_drawWaypoints[i]={lng,lat}` and `_drawLegs[i]={coords,distance}`
(index-aligned, one shorter than `_drawWaypoints`). A live distance readout
(`drawTotalDistance()`) shows in the `#mode-banner` UI, along with Cancel
(`cancelActiveMode`) and Finish (`finishDrawRoute`) — **`cancelDrawOnly`
bumps a `_drawSession` counter**, and every async `recomputeDrawLeg` checks
it against the value it started with (before AND after its network call)
before writing to `_drawLegs`; without this, a slow Directions response that
resolves after the user has already hit Cancel could silently repopulate a
leg the user thought they'd cleared, making Cancel look broken. Straight
segments in the drawn line are usually not a bug: Mapbox's Directions API
has no dedicated hiking/trail profile, so `foot`→`walking` frequently has no
path data for off-trail routes and falls back to a straight line between
the two points — the insert/drag capability above is the intended fix for
that, not a deeper snapping algorithm. **v1 deliberately does not include**
(add as new functions/UI when picked up, don't retrofit into the existing
ones): undo/redo, right-click/long-press context menus on points or
segments, or an elevation profile display.

**Airport pins** (was a standalone "Airports" view/nav item in an earlier
draft of this branch — the user explicitly asked to drop that and fold it
into Pins instead, 2026-09-04). `computeAirportGroups()` scans `getMoments()`
for `getGroup(type)==='Flight'`, reads each Moment's two endpoints (falling
back to the decoded polyline's last coordinate, grouped by rounded
coordinate under label `'Unknown airport'`, for flights that predate
`endLat`/`endPlace` — this is most real flight data, since only NL-parser-
created Flight Moments populate those fields; Strava/GPX imports never do),
and returns one group per airport with a sorted `visits` array
(`{date, momentId}`). **`syncAirportPins()` resolves an `'Unknown airport'`
group's real name via `reverseGeocodeAirport(lat,lng)` before pinning it —
it does NOT skip unlabeled flights** (an earlier version of this code did
skip them, which meant zero airport pins ever appeared for anyone whose
flight data came from Strava/GPX rather than the NL parser — caught via user
report, not by the test harness, since the harness only ever exercised
NL-parser-created flights which already have labels). `reverseGeocodeAirport`
is deliberately NOT Mapbox's reverse-geocoding endpoint — checked
empirically: reverse geocoding with `types=poi` returns zero results even
for the Eiffel Tower in this Mapbox setup, and an unfiltered reverse lookup
returns a street address, not a landmark name. It's a proximity-biased
*forward* search for the word `"airport"` instead, which reliably returns a
real, location-correct name — often a nearby road ("Airport Road, Los
Angeles") rather than the airport's official name, which is a Mapbox
indexing quirk, not a bug worth fighting further. Falls back to
`"Airport near {lat}°, {lng}°"` only if that search itself returns nothing.
Because the resolved name is decided once (at pin-creation time) and
`computeAirportGroups()` itself never resolves names, `showDetail`'s visit-
metadata lookup for an airport pin matches by name OR by coordinate
proximity (`Math.abs(g.lat-mem.startLat)<0.05`) — name-matching alone would
silently show no visit history for any reverse-geocoded pin.
`syncAirportPins()` creates a Pin (category `airport`) for any airport that
doesn't have one yet, matched by name (`startPlace`) against existing
airport pins — so it's safe to call repeatedly/liberally (called from
`renderAll()` and after anything that can newly produce a Flight Moment:
`doImport`, `saveManualEntry`, `saveParsedRoute`). **The pin itself persists
(so it shows up as a map marker like any other pin); its visit metadata does
not** — the detail panel always recomputes first-visit/count/all-visit-dates
fresh from `computeAirportGroups()` rather than reading stored fields, so
metadata can never drift out of sync with the flights it's derived from if
one is later edited/deleted. Do not add a `visitCount`/`lastVisit`/etc.
field to the pin itself and start writing it — that reintroduces the exact
drift risk this design avoids.

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

- Draw-route: drag-to-reposition a point AND click-the-line-to-insert-a-point
  ARE built (see above) — what's still deferred is undo/redo, point/segment
  context menus, elevation profile.
- NL parser: mixed-mode sentences ("drove to X, then flew to Y"). The
  preview map's insert-on-click IS built (see above), same as draw-route.
- Airports: no standalone view any more (removed per the user's request) —
  airport pins ARE rendered as ordinary map pins now, so the earlier "not
  rendered as pins" follow-up is done, not deferred.
- Pin-drop mode: clicking exactly on an existing pin marker while in pin-drop
  mode does nothing (the marker's own click handler absorbs the click before
  it reaches the map canvas) rather than dropping a new pin at that spot.
