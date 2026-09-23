# Main map UX review — buttons, filters, controls (2026-09-23)

Scope: the map view only (`#map-view`) — the top-left Activities pill, the
top-right control stack (`#map-tools`), the filter drawer
(`#filter-drawer`/`buildFilterDrawer()`), and the sidebar (`#sidebar`). Not
in scope: Feed, Profile, Activities table view, Story/Relic builder — those
have their own patterns and mostly work fine.

This is a findings document, not an implementation plan. No code changed.

## Headline problem

Selecting/deselecting what to show is scattered across **three separate,
differently-shaped controls** that don't share a mental model:

1. **Sidebar sort row** (`.sb-sort-row`) — 5 always-visible text buttons
   (Recent/Name/Distance/Elevation/Type). This is sort, not filter, but it
   sits directly above the filter chip row with identical visual weight, so
   it reads as "another filter."
2. **Filter drawer** (`#filter-drawer`) — 10 collapsible sections (Activity
   type, Source, Date, Distance, Duration, Elevation gain, Heart rate, Mood,
   Attributes, Pins, Track colours, Track thickness), each collapsed by
   default, opened via a small icon-only button top-right.
3. **Active-filter chip row** (`renderFilterChips()`) — a *third* place that
   shows what's currently filtered, with its own per-chip × buttons plus a
   "Clear all."

A user who wants to "just show running and hide walking" has to: find the
sliders icon (no label, easy to miss among 6 other icon buttons), open the
drawer, find "Activity type" (1 of 10 stacked sections, needs a click to
expand since every section starts collapsed), then click individual
type rows one at a time. There's no "select just this one / all but this
one" gesture — see below.

## Specific findings

### 1. Toggling types is all-or-nothing-per-click, with no fast path for the single most common intent
`toggleFilterType()` / `_setTypeSet()` (index.html:3943-3951) only supports
flipping one type at a time. The single most common thing a user wants
("show me only my runs") takes **N-1 clicks** (deselect everything else) or
requires first clicking "Clear all" then deselecting everything except the
one type you want to isolate — there's no "solo" affordance (click = show
only this; shift/long-press = toggle this one) the way most filter UIs
(Figma layers, Gmail labels, Notion) offer. Every section that uses
`_setTypeSet` (type, source, mood) has the same gap.

**This is very likely the "cumbersome" complaint's biggest single source** —
it's the highest-frequency filter action in the app and it's the most
expensive one to perform.

### 2. Every section starts collapsed — so "seeing what's on" costs a click every time
`_fdCollapsed` defaults everything closed (`sec()` at index.html:3845-3851
checks `_fdCollapsed.has(id)`). Combined with #1, a user re-opening the
drawer to change one type toggle has to: open drawer → expand "Activity
type" → find the row → click it → (maybe) collapse it again. The dot
indicator (`.fd-dot`, shown via the `active` class) at least signals *which*
sections have a non-default filter without opening them — that part works —
but it doesn't show *what* the filter is, so the user still has to open the
section to check or change it.

### 3. Three visually-similar row types with different click targets, in the same section
Inside "Activity type" each row (`.tp-type-row`) is: a colour dot (inert),
a label (inert), and a small toggle pill (`.tp-type-toggle`) — but the
`onclick` is on the *whole row* (`tp-type-row`), while in "Pins"
(`fd-sec-pins`) the row is split — the label has its own `onclick`, the
toggle has its own `onclick`, but the colour swatch is a third, separate
`<input type=color>` target. Whole-row-clickable in one section,
split-target in the next section, is inconsistent and makes it easy to
mis-tap a colour picker when meaning to toggle visibility, or vice versa.

### 4. The "solo" instinct doesn't exist anywhere, but "Clear all" does — twice
There's a `clearFilters()`/"Clear all" in the drawer footer, *and* a second
"Clear all" chip at the end of the active-filter chip row
(`renderFilterChips()`, index.html:4026) that does the exact same thing.
Meanwhile there's no equivalent one-click "keep only this" — the operation
users actually reach for constantly (isolate one sport) has zero affordance,
while the rare "reset everything" operation has two.

### 5. Range filters (Distance/Duration/Elevation/HR) are raw two-input boxes, no visible bounds
`_fdRange()` (referenced at index.html:3931-3934, not shown above) renders
as plain min/max number inputs per the calling pattern. Without a slider or
visible min/max of the user's own data, a user has to guess "was my longest
run 40km or 4km?" before typing a sensible upper bound — friction that a
dual-handle range slider (bounded to the user's actual min/max, like the
"Track thickness" slider already does at index.html:3906-3912) would remove
entirely. Track thickness got a slider; the four numeric range filters,
which are used far more often, didn't.

### 6. The filter icon button carries no label and no filter count
`#tools-toggle-btn` (index.html:1976) is icon-only with a single generic
title tooltip ("Filters") and an `mt-badge` that's `hidden` by default —
worth checking whether it's actually wired to show the active count (the
Activities-view equivalent, `#av-fcount`, clearly is, per
`renderFilterChips()` line 4032, but the map's `mt-filter-badge` id doesn't
appear to be set anywhere in that function). If it isn't wired up, a user
has no way to tell "are filters currently hiding something?" without
opening the drawer — the map could just look empty/sparse with no visible
cause.

### 7. Sort, filter-chips, and search are stacked with near-identical visual weight
`.sb-sort-row`'s 5 buttons sit directly under the search box and directly
above the filter-chip row, all in the same small sans-serif at similar
size/colour (index.html:1896-1907). Sort ("how is the list ordered") and
Filter ("what's excluded") are different operations but look like one
continuous control strip. A first-time user scanning this stack has no
visual cue for where "what's shown" ends and "what order" begins.

### 8. The control cluster top-right mixes camera controls, layer/terrain toggles, and filters with no grouping logic beyond CSS `.mt-group`
Reading `#map-tools` top to bottom: layers+filters, then fit-to-bounds +
reset-north, then zoom in/out. That's a reasonable *visual* grouping
already (three `.mt-group` clusters), but "Filters" — the thing this review
is about — sits wedged between "map style" and "camera," i.e. filed under
map chrome rather than given its own distinct entry point. Everywhere else
in the app filters get a labeled pill/button with a count
(`.av-filter-btn` in Activities view, index.html:2038, literally says
"Filters" with a visible count chip) — the map is the one place filters
are demoted to an unlabeled icon in a row of camera buttons.

## What's actually working well (keep these)

- **Active-filter chips with per-chip removal** (`renderFilterChips()`) are
  the right pattern — a user can see and undo exactly what's filtered
  without opening the drawer. The gap is that this same "chip" idea isn't
  extended to a faster way of *building* the filter state in the first
  place.
- **"Only the groups this user actually has tracks in"**
  (index.html:3853-3856, `usedGroups`) is good discipline — not showing 18
  possible sport types when someone only has 3. This principle isn't
  applied as consistently elsewhere (Mood shows every mood + "no mood"
  regardless of use; Attributes always shows all 3 regardless of whether
  the user has ever set them).
- **The `.fd-dot` active-section indicator** is a good lightweight way to
  scan "which of these 10 sections has something non-default set" without
  opening each one.
- **Track thickness's slider with a live numeric readout** is the interaction
  pattern the numeric range filters should be borrowing from, not the other
  way around.

## Recommendations, roughly in order of impact/effort

1. **Add a "solo" gesture to type/source/mood toggles.** Clicking a row's
   label solos it (show only this, one click); clicking the toggle pill
   itself keeps the current add/remove-one-of-many behavior. This alone
   fixes the "select and deselect is a pain" complaint for the single most
   common case, with no new UI chrome — just a second behavior on an
   existing target, same pattern already half-present in the Pins section's
   split label/toggle click targets (finding #3) — make that split
   consistent across all three sections and give it a job.
2. **Give the map's filter button a visible label + live count**, matching
   `.av-filter-btn` in Activities view exactly (icon + "Filters" + count
   chip), rather than a bare icon. Confirm `#mt-filter-badge` is actually
   populated; if it isn't, that's a real (if minor) bug worth a one-line fix
   regardless of the rest of this review.
3. **Auto-expand "Activity type" (and any section with `active` state) the
   first time the drawer opens** rather than every section starting
   collapsed — it's the section nearly everyone touches first.
4. **Turn distance/duration/elevation/HR into a single dual-handle slider
   each**, seeded from the user's actual min/max (already computed as
   `filterBounds`, reused by these sections already) — same visual language
   as Track thickness, so the drawer stops mixing slider and raw-number-box
   interaction styles.
5. **Visually separate Sort from Filter in the sidebar** — different label
   weight/colour, or a thin divider, so the sort row doesn't read as a sixth
   filter category.
6. **Consider collapsing the two identical "Clear all" controls into one** —
   the drawer footer's is redundant with the chip row's once both are
   visible at once (drawer open + chips populated).

None of this requires a new information architecture — the drawer's
section-per-facet model and the chip-row summary are both sound. The fix is
almost entirely about (a) cutting clicks for the one operation people do
constantly (isolate a type) and (b) making the filter entry point as
visible/labeled on the map as it already is in Activities view.
