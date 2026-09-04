# Plan — persistent map settings, richer filtering, nav cleanup

**Status: built** (commit after `246c22f`). Decisions taken: resume the last map
camera (overrides the autoframe); the stats/Archive page is parked, not moved.
See "## What shipped" at the bottom.

Branch: `map-filters` (off `main` @ `a2974eb`).
Everything is in `index.html` (single-file app). Desktop layout stays put; new
UI lives behind the existing `@media (max-width: 768px)` guards where it differs.

Scope, in order:

1. Map remembers the settings you've selected
2. Many more filter dimensions (any field we store)
3. One coherent filter panel to drive them
4. Nav becomes **Map · Feed · Activities · Profile** — the "Archive" page goes away

Deferred (noted, not this branch): profile redesign, full visual redesign,
saved/named filter presets, slider histograms.

---

## 1. Persist map settings per user

**Today** nothing about the map view survives a reload. State lives in loose
globals: `activeTypes` (Set, `index.html:1448`), `activeYears` (Set, `:1449`,
repopulated from data every load at `:1902` / `:3234`), `sidebarSort` (`:1451`),
`terrainOn` / `satelliteOn` (`:1446`), and per-type colours (already persisted
separately in `relic_colors_v1`, `loadColors()`).

**Plan**

- New per-user key `relic_mapprefs_v1_<uid>`, following the `_cacheKey()` /
  `saveArchiveCache()` pattern at `index.html:1618`.
- Persist: the whole `filters` object from §2, `sidebarSort`, `terrainOn`,
  `satelliteOn`. Fold `relic_colors_v1` into this key too (one read, one write)
  — keep a one-time migration that reads the old key if present.
- `saveMapPrefs()` debounced (~400 ms), called from every filter mutation and
  the basemap toggles.
- `loadMapPrefs()` in `bootRelic`, **before** the first `applyFilters()` and
  `buildToolsPanel()`.
- Reconciliation: date/year filters must not silently hide activities that
  appeared since the prefs were saved. Store date filters as an explicit range
  (`dateFrom`/`dateTo`) or "all", not an enumerated year Set, so new imports
  inside the range just show up. If we keep year pills, newly-seen years default
  **on**.
- **Not** persisting map camera (center/zoom/pitch) — the fast-onboarding
  autoframe (`f5c25ba`) should keep winning on load. Open question if you want
  "resume where I left off" instead.

---

## 2. Expanded filter model

Replace `activeTypes` + `activeYears` + the bare search string with one object:

```js
let filters = {
  search:      '',
  types:       new Set(),        // TYPE_CONFIG keys (Run, Ride, …)
  sources:     new Set(),        // 'strava' | 'import' | 'kml_import' | 'manual'
  dateFrom:    null,             // 'YYYY-MM-DD' | null
  dateTo:      null,
  distanceKm:  [null, null],     // [min, max]
  durationMin: [null, null],     // minutes
  elevationM:  [null, null],
  speedKmh:    [null, null],     // avg_speed-derived
  hr:          [null, null],     // avg_hr
  moods:       new Set(),
  hasPhotos:   null,             // null | true | false
  hasStory:    null,             // note present
  commute:     null,
};
```

One predicate — `matchMoment(m, filters)` — is the single source of truth,
consumed by `applyFilters()` (`index.html:1967`, drives the map source + the map
sidebar list) **and** the new Activities view (§4). One shared `filters` object
across both, so "the map remembers what I picked" and Activities show the same
set.

Fields we already store and can filter on (`rowToMoment`, `index.html:1503`):

| Group | Fields |
|---|---|
| Core | `type` (grouped), `source`, `date` |
| Effort | `distance`, `duration`, `elapsedTime`, `elevation`, `elevHigh`/`elevLow` |
| Performance | `avgHR`, `maxHR`, `avgSpeed`, `maxSpeed`, `avgCadence`, `avgWatts`, `weightedWatts`, `sufferScore`, `calories` |
| Flags / meta | `mood`, has photos, has note/story, `commute`, `prCount`, `achievementCount`, `workoutType` |

**Dynamic bounds & relevance:** on load, compute min/max per numeric field over
the dataset to set slider ranges, and **hide any filter whose field is entirely
empty** (e.g. no power meter → no watts filter). Recompute after a sync.

---

## 3. The filter panel

Replace the 2-tab tools panel (`buildToolsPanel()`, `index.html:2019`; Types /
Colors) with one **Filters** panel.

- **Open it:** the existing ⚙ FAB on mobile (`#filter-fab-mobile`,
  `index.html:1126` — currently just calls `toggleSidebar()`); a "Filters"
  button in the desktop sidebar header.
- **Structure** — collapsible sections, only the first two open by default:
  1. **Activity** — search box, type pills (multi-select), source pills
  2. **When** — date range + presets (This year / Last 12 months / All time);
     optional month + weekday pills
  3. **Distance · Time · Climb** — dual-handle range sliders + paired numeric
     inputs; bounds from data
  4. **Performance** — HR / speed / power / suffer; whole section hidden if no
     such data
  5. **Attributes** — mood pills, has photos, has story, commute
  6. **Appearance** — per-type colour pickers (moved out of the old Colors tab),
     basemap (3D terrain / satellite toggles relocated here or kept on the map)
- **Active-filter bar** (always visible, above the list / under the search):
  one removable chip per non-default filter, a "Clear all", and the live
  `N of M activities` count (the count already exists at
  `#result-count`, `index.html:1982`).
- **Apply behaviour:** desktop live-applies on change; mobile is a full-height
  sheet (reuse the existing sheet pattern) with a sticky `Show N activities`
  button so slider drags aren't thrashing the map.
- Collapsed sections show a small badge when they hold an active filter.

Phase-2 polish (not now): save named presets to the prefs key; mini histogram
in slider tracks.

---

## 4. Nav: drop Archive, add Activities

**Today:** Map · Feed · **Archive** · Profile, where "Archive" is
`#stats-view` / `buildStats()` (`index.html:1207`, `:2597`) — a stats page
(stat grid, heatmap, distance-by-type, year-by-year), *not* a list.

**Target:** Map · Feed · **Activities** · Profile.

- Rename throughout: view `stats-view` → `activities-view`; `nav-stats` →
  `nav-activities`; `switchView('stats')` → `switchView('activities')`; the
  desktop nav button (`index.html:1071`), the mobile menu item (`:1086`), the
  bottom tab (`:1283`) — glyph + label. `switchView` dispatch at `:3764`.
- **Activities view = full filterable/sortable list** of every activity (no 300
  cap like the map sidebar's `renderList()` at `index.html:1994`):
  - Driven by the shared `filters` object + a "Filters" button opening the same
    panel from §3.
  - Table-ish rows: name · date · type · distance · duration · elevation, with
    optional columns (HR, pace, mood, 📷). Click a column header to sort.
  - Row click → jump to it on the map (`switchView('map')` + `flyToTrack`), or
    open the detail panel. Comfortable/compact density toggle. CSV export later.
- **The stats content** (heatmap / breakdowns / year timeline) moves onto the
  **Profile** page as a "Stats" block — rough placement is fine now; it gets
  cleaned up in the later profile pass. `statsBuilt` guard (`:1453`, `:3764`)
  moves with it.

**Open question for you:** move the stats onto Profile now (a bit rough), or
park them in a collapsed section until the profile redesign?

---

## Touch list

- `index.html`
  - filter state + `matchMoment` — around `:1448`, `:1967`
  - `buildToolsPanel` / tools panel markup + CSS → filter panel — `:2019`, `:193`, `:823`
  - `loadMapPrefs` / `saveMapPrefs` + `bootRelic` wiring — near `:1618`, boot path
  - nav rename (3 places) + `switchView` — `:1069`, `:1084`, `:1281`, `:3756`
  - `stats-view` markup → `activities-view` + Activities list renderer — `:1207`
  - move stats blocks onto `#profile-view` — `:1222`, `buildStats` `:2597`
  - `activeYears` default-on logic — `:1902`, `:3234`
- `docs/setup.md` — document the `relic_mapprefs_v1_<uid>` key
- `archive/` (the frozen v1) is untouched — this is only about the live app's
  "Archive" tab

## Suggested build order

1. `filters` object + `matchMoment`, refactor `applyFilters` to use it (no UI
   change yet — behaviour identical with all-on defaults)
2. `loadMapPrefs`/`saveMapPrefs` — persistence of the current (small) filter set
3. Filter panel shell + active-filter bar, port Types/Colors into it
4. Add the new filter sections (date, ranges, performance, attributes)
5. Nav rename + Activities list view on the shared filter state
6. Relocate stats to Profile

---

## What shipped

All in `index.html`. `?demo` on localhost/`file://` seeds ~48 synthetic
activities and runs offline behind a stub map (no Mapbox token needed) for
testing.

- **`filters` object + `matchMoment(m, f)`** — one predicate for the map tracks,
  the map sidebar list, and the Activities list. Dimensions: search, type,
  source, mood (incl. "no mood"), date range, distance, duration, elevation
  gain, avg HR, has-photos, has-note, commute. `null` on a set field = "all"
  (new types/sources appear automatically). Range bounds shown from data;
  HR section hidden when no HR data.
- **Filter drawer** (`#filter-drawer`) — right-side slide-over, opened from the
  map toolbar ⚑, the mobile FAB, and the Activities "Filters" button. Collapsible
  sections (type / source / date / distance / duration / elevation / HR / mood /
  attributes / track colours), a dot on any section with an active filter.
  Replaces the old 2-tab tools panel; `#tools-panel` is now dead, `toggleToolsPanel`
  is a shim.
- **Active-filter chip bar** — `#filter-chips-map` (sidebar) + `#filter-chips-activities`,
  one removable chip per active filter + "Clear all". "all except X" phrasing
  when most of a set is on. `#av-fcount` badge on the Activities Filters button.
- **Activities view** (`#activities-view`) — replaces the Archive tab. Full
  sortable table (name/date/type/distance/time/elev/HR), no 300-cap, driven by
  the shared `filters`. Row click → `goToActivity()`. Nav renamed in all three
  places; `switchView('activities')`.
- **`stats-view` parked** — `hidden`, not in nav. `buildStats()` still defined.
- **Persistence** — `relic_mapprefs_v1_<uid>`: `filters`, `sidebarSort`,
  `terrainOn`, `satelliteOn`, `camera`. `saveMapPrefs()` (400ms debounce) from
  every filter mutation, sort, basemap toggle, and `moveend`. `loadMapPrefs()` +
  `applyStoredFilters()` restore before the first render.
- **Camera resume** — `moveend` captures `{center,zoom,pitch,bearing}`; on load
  the stored camera seeds the `Map` constructor and sets `_framedOnLoad` so the
  autoframe is skipped. `relic_colors_v1` left as its own key (unchanged).

### Not done (still deferred)
Dual-range sliders (used number inputs), slider histograms, saved filter presets,
moving stats onto Profile, profile redesign, visual redesign.

### Follow-ups / risks
- Real Mapbox path is unchanged and untested here (can't load tiles in this
  env) — needs a `pages.dev` deploy check: filter drawer open, camera resume,
  terrain/satellite restore.
- `#tools-panel` element + `.tp-tab`/`.tp-pane` CSS are now dead — remove in a
  later tidy.
