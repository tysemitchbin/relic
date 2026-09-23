# Relic — CLAUDE.md

Relic is a personal life-map app: a single `index.html` (~8,300 lines), no
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
- `TYPE_CONFIG` (tracked activity *groups*) lives in **`activity-types.js`**,
  the one exception to "everything is in `index.html`": a plain `<script src>`
  shared with `relic-bulk-import.html` so the two can't drift (they used to
  keep separate hardcoded lists). It also holds `getGroup`/`getColor`/
  `usesSpeed`/`isCycling`/`typeOptionsHtml`. Colours persist in
  `relic_colors_v1` (localStorage). These are for GPS-shaped Moments — do not
  add pin categories into `TYPE_CONFIG` (see below). Since `travel-modes`
  (2026-09-19) every GPS-shaped Strava SportType maps into a group; non-GPS
  sports (gym, yoga, court/ball sports, climbing, virtual rowing) are
  deliberately left out and fall to Other (user's call). Cycling is split
  Road Bike (key still `Ride`) / `MountainBike` / `Gravel`, and `Alpine` /
  `Snowboard` are separate — the user was explicit that people are picky
  about these. Group keys are persisted, so never rename one.
  Per-group flags: `kind:'travel'` (Flight/Drive/Rail/Boat/Motorbike — Relic's
  own modes), `speed:true` (km/h, not pace — ask `usesSpeed(type)`, never
  hardcode group names), `cycling:true` (cadence in rpm). `types[0]` is the
  value stored when a group is picked by hand; type `<select>`s are built by
  `typeOptionsHtml()`, not hardcoded. Strava sync stores `sport_type` (falls
  back to legacy `type`).
- **Users can change a track's type** (picker in the detail header,
  `onTypeChange`). That sets `_typeEdited` / the `type_edited` column, which
  `strava_upsert_activities()` respects so a resync never overwrites it —
  same pattern as `_nameEdited`/`name_edited`. Needs
  `docs/supabase-type-edit.sql` live before the client ships.
  NL parser routing goes through `ROUTE_PROFILE`; modes absent from it
  (Rail/Boat/Paddling) get straight lines, not road-snapped routes. The
  filter drawer's type toggles and "Track colours" only list groups the user
  has at least one track in (user's request).

## Design system + social layer (`ux-social-overhaul`, 2026-09-18)

Full rationale lives in `docs/review-2026-09-18.md`. What future edits need
to know:

- **Brand palette:** see `docs/brand-colors.md` (rust `--brand-rust` #C1502E is
  the one constant; light mode is the app, forest-dark only for hero screens).
  Map tracks do NOT use the brand palette and are defined in
  `activity-types.js`: bright colours, no dark casing (tried and rejected),
  and since 2026-09-20 a hue is deliberately **reused** in a different shade
  by activities that never sit side by side (red = Run/Motorbike, blue =
  Road Bike/Swim/Boat…). A new type takes another shade in an existing
  family rather than a new hue. Pins default to white for every category;
  users set colours in Filters → Pins.
- **Tokens, not literals.** Colours/radii/shadows/fonts are CSS variables on
  `:root` (`--bg`, `--surface`, `--text`, `--text-2`, `--text-3`, `--accent`,
  `--r-*`, `--sh-*`, `--font-ui` = Inter, `--font-display` = Fraunces,
  `--font-mono` for coordinates only). The legacy names (`--ink`, `--paper`,
  `--paper2`, `--muted`…) still exist and point at the new palette.
  `--text-2`/`--text-3` are the AA-contrast secondary colours — don't
  reintroduce the old `#8a8278`-on-paper greys. Nothing below 11px; no
  letter-spaced monospace uppercase on buttons (sentence case).
- **Buttons:** `.btn-primary` (accent), `.btn-primary.dark`, `.btn-ghost`,
  `.btn-sm`, `.danger`; `.follow-btn`; `.fc-act` (feed card actions);
  `.seg` segmented control; `.switch` toggle; `.chip`. Reuse these rather
  than adding another one-off button class.
- **Icons:** inline SVG sprite at the top of `<body>` (`#icon-sprite`), used as
  `<svg class="ic"><use href="#i-name"/></svg>`. Add new icons as `<symbol>`s
  there (24px grid, stroke). No unicode glyphs as UI icons.
- **Dialogs:** never `alert()`/`confirm()`. Use `toast(msg, {error, icon,
  action})` and `await uiConfirm({title, body, ok, danger})`.
  For a small form use `await uiForm({title, sub, bodyHtml, ok, validate})`
  (resolves to `{name: value}` of its `[name]` inputs, or `null`).
- **Bulk edits:** Settings → Sharing → *Manage activities* (`openBulkEditor`)
  has its own filter state (`_be`, deliberately separate from the map's
  `filters`) and selection (`_beSel`). Privacy changes go through
  `applyBulkPrivacy`, field edits (type/colour/name) through `applyBulkEdit`
  — both chunk writes, refresh `activity_public` snapshots, and roll back only
  unsaved chunks. Add new bulk actions to `beMoreMenu()` using those.
- **Modals on mobile** (<=768px) become bottom sheets. Two rules learned the
  hard way (2026-09-20, from a user report about the "+ Add" sheet):
  1. Every modal needs a *visible* dismiss control — a `.modal-actions`
     Cancel (sticky at the bottom of the sheet on mobile) and/or backdrop
     tap-to-close (`onclick="if(event.target===this)closeX()"`, the
     `#lightbox` pattern). The global Escape handler is desktop-only, so a
     modal without one is a dead end on a phone. `#add-modal` shipped with
     neither and was unexitable.
  2. Never size anything inside `.modal-overlay` with `100dvh`. The overlay
     is `position: fixed`, so iOS Safari lays it out against the *small*
     viewport while `100dvh` is the *large* one; with
     `align-items: flex-end` the sheet then overflows off the **top** of the
     screen, and the overlay isn't scrollable, so the title and first rows
     are unreachable. Use `calc(100% - ...)` — a percentage of the overlay.
     Same trap as `#app`'s layout notes in the mobile media query.
- **Escaping:** anything user-authored that goes into an HTML string goes
  through `escapeHtml()`; ids/strings passed into inline `onclick` go through
  `jsAttr()`. Friends' content is rendered now, so a miss is cross-user XSS,
  not self-XSS.
- **Social data layer:** all social reads/writes go through the `Social`
  object (profiles, graph, follow, feed, stories, photos, kudos, comments,
  notifications, suggestions, block, report). `?demo` swaps in `DemoSocial`
  (a synthetic cast of friends) via `Object.assign(Social, DemoSocial)` —
  **add any new `Social` method to `DemoSocial` too**, or `?demo` breaks.
  UI code never branches on `DEMO`. `?demo` never writes to Supabase
  (`persistMoments` / `flushDirty` short-circuit).
- **Tables that may not exist yet** (`kudos`, `comments`, `story_public`,
  `blocks` — all in `docs/supabase-social-v2.sql`): the client detects a
  missing relation with `isMissingTable(err)` and flips `_socialOff.<x>`,
  which hides that UI. Keep new social tables optional the same way until
  the SQL has been run in production.
- **Public snapshots:** non-owners only ever read `activity_public` /
  `story_public` — redacted on the owner's device (`buildPublicSnapshotRow`,
  `buildStorySnapshotRow`, via `redactTrackForPrivacy`). A story is public iff
  it has a `story_public` row (no column on `stories`). Never expose raw
  `activities` rows to other users.
- **Notifications** are derived (follows/kudos/comments aimed at you, newest
  first) with a per-device "last seen" in localStorage — there is no
  notifications table. Compare timestamps with `Date.parse`, not strings.
- **Deep links:** `?u=<user>` opens a profile, `&a=<activity>` / `&s=<story>`
  focuses a card. `captureDeepLink()` stores it (so it survives sign-up /
  email confirmation) and strips it from the URL; `handlePendingDeepLink()`
  runs from `afterBoot()`.
- **Views:** `feed` (Following/You tabs + `#feed-top` checklist/"On this day"),
  `people` (Discover/Following/Followers tabs — the follower lists moved here
  from the old People page; the profile's Followers/Following stats open
  them via `openConnections()`), `public-profile` (hero + a static cover band
  of their public tracks — see "Profile = Stories only" below for where the
  interactive map actually lives now). The map's activity list (`#sidebar`)
  opens from the `#list-toggle` pill.

## Profile = Stories only (2026-09-20)

The user was explicit: Profile (yours or someone else's) is not another
activity list — Strava already does that. It's Stories, curated. Individual
Moments/activities live behind a click, not on the page.

**UI label vs. code (2026-09-20):** everything a person sees now calls this
"Relic" ("New Relic", "Relics", "Delete this relic?", etc.) — the user asked
for the rename explicitly, scoped to visible text only. Every internal name
stays "Story"/`story` on purpose: `isStory()`, `getStories()`, `openStoryModal`,
`saveStory()`, `.story-card`/`.story-modal`/`#sm-*` CSS and ids, the
`stories`/`story_public` Supabase tables and columns (`story_id`, …), the
`type:'story'` value stored on the object itself. Don't "helpfully" rename
any of that to match the UI — it's unrelated code, and renaming the table
needs a migration nobody has asked for. If a future ask does want the code
renamed too (or the database), treat it as new scope, not a continuation of
this one. One unrelated concept that intentionally did **not** get renamed:
"Has story note" (the filter drawer) and the `'story'` badge in the map
sidebar list both mean "this individual Moment has a written note"
(`m.note`) — nothing to do with the Story/Relic entity, so they keep saying
"story" in that different sense.

- **Profile page itself** (`#profile-view` / `#public-profile-view`) now
  shows only: header (photo/name/bio/stats, or avatar/name/bio/stats for a
  public profile), a **map hero** (`.profile-cover-wrap` wrapping
  `#profile-cover` on your own profile / `#pp-cover` on a public one — both
  reuse the same `.profile-cover` static-image-band styling and rendering
  helper, `renderProfileCover()` for your own, `renderPublicCover(acts)` for
  someone else's), and **Stories** (`renderProfileStories()` /
  `renderPublicStoryCard()` inside `#pp-body`). There is no "Moments"
  honeycomb grid or "Activities" list anywhere in Profile — not on the page,
  and (2026-09-20) not in the map-hero modal either, see below. Both stories
  sections show an `emptyBlock()` empty state (not a hidden section) when
  there are none yet, with a "New story" CTA — the point is to nudge people
  toward making one, not to look broken.
- **The map hero is clickable** (`onclick="openProfileMapModal(...)"`,
  `role="button" tabindex="0"`, same plain-div-as-button pattern as
  `.profile-stat[onclick]` elsewhere in this file) and opens
  `#profile-map-modal` — an interactive map (`#pmm-map`, `_pmmMap`,
  `renderPmmMap(tracks, focusActivityId)`) of every track privacy allows.
  **Map only, no list of any kind** — an earlier version of this modal also
  showed a Moments honeycomb grid (own profile) or a feed-card activity list
  (someone else's); the user explicitly said no activity list anywhere and
  no honeycomb grid, so both were deleted along with their support code
  (`renderProfileHoneycomb()`, `drawMiniMap()`, `setProfileSort()`/
  `profileSort`, the `.hex-*` CSS, `#pmm-body` and its children). Don't
  resurrect any of that inside this modal — if a browsable list is wanted
  again, it belongs on its own page, the way Activities does below.
- **It's a genuine full-screen takeover, not a floating dialog** (user
  feedback, 2026-09-22, after the first version rendered as a small centered
  card — "want to open a full map, not just a pop up window"). `#profile-map-
  modal` and `.profile-map-modal-inner` override the generic `.modal-overlay`/
  `.modal` centered-card treatment directly (`padding:0`, `width/height:100%`,
  `max-width/max-height:none`, `border-radius:0`) so it fills the whole
  viewport — including over the header, since `.modal-overlay`'s z-index
  (500) already beats `#header`'s (200) — at every screen size, not just
  the mobile bottom-sheet breakpoint. The mobile media query only adds
  safe-area padding to `.pmm-head` and drops the bottom-sheet drag-handle
  `::before` (not a sheet any more). If a future modal ever wants this same
  full-bleed treatment, copy this pair of overrides rather than fighting the
  base `.modal` sizing per breakpoint.
- **The map inside this modal has most of the main map's controls** (user
  ask, 2026-09-22) — a layers popover (`#pmm-layers-pop`, same `.lp-*` CSS as
  the main map's) with Standard/Satellite + 3D terrain, a "Show everything"
  fit button (`fitPmmMap()`), reset-north, zoom, and a bottom-left legend
  (`pmmBuildLegend()`) of the activity-type colors present, built from
  `TYPE_CONFIG` (so it reflects any user recoloring) rather than per-track
  `customColor`. No `cooperativeGestures` on this map (unlike the main map's
  embed elsewhere) — it's a genuine full-screen takeover per the point above,
  not a page fighting the map for scroll, so requiring ctrl+scroll to zoom
  was just friction (user report). The controls/legend markup are DOM
  siblings of `#pmm-map`, not children of it — `renderPmmMap()` does
  `el.innerHTML=''` on that container on every (re)open, which would
  otherwise wipe them. **"Your tracks" comparison overlay**: on someone
  else's map only (`#pmm-mine-row` hidden when `_pmmIsOwn`), a switch loads
  every one of *your* Moments as a second line layer (`pmm-mine-lines`,
  dimmed, `line-opacity:0.32`) added with `beforeId:'pmm-lines'` so their
  tracks always render on top of yours — lets someone compare their map
  against a friend's. Because `mapboxgl.Map#setStyle` (the satellite toggle)
  wipes any source/layer not baked into the style, every `pmm-*` source/layer
  add is idempotent and funneled through one function (`pmmAddLayers()`,
  called from both the map's first `style.load` and every subsequent one) —
  don't add a new pmm layer as a one-off `.on('load', ...)` call the way the
  original single-layer version did, it'll vanish the moment someone flips
  Satellite.
- **Your own individual activities have their own page**: `#activities-view`
  / `renderActivitiesView()` (a sortable table, pre-existing — see "Filters +
  Activities view" below) is reachable from the header nav *and*, since
  2026-09-20, from the account-avatar dropdown (`#account-menu`, "Your
  activities", right next to Settings) — the user asked for a dropdown entry
  point and this already-existing view was the natural fit, so no new view
  was built. It only ever shows your own Moments; there's no equivalent
  "browse all of someone else's activities" page — a visitor sees another
  person's individual activities only via Stories and the Following feed.
- **`isOwnContext` (the modal's 3rd argument) must come from the caller, not
  from `userId === currentUser.id`.** You can land on your *own*
  public-profile page — a deep link to your own shared activity, or "View on
  profile" from your own map popup — and that must still use the
  already-fetched public `acts` (what a visitor would see), not every
  private Moment you have. Only the map hero on your actual `#profile-view`
  passes `true`; the public-profile hero and the internal deep-link call
  (`openProfileMapModal(userId, focusActivityId)` at the end of
  `openPublicProfile`) both omit it, so they always take the "public" path
  even when `userId` happens to be you.
- **A Story can be just one moment** (`saveStory()` only requires 1+, back
  to the original rule — a same-session 2+ minimum was tried and reverted:
  the user, on reflection, was fine with a single-activity Relic). Grouping
  is otherwise free-form (search/type/date filters in the story modal
  already support both "this trip" and "Walks in May" style themes) — no
  code change needed there.
- **Relic suggestions** (`relic-suggestions`, 2026-09-23): the above deferred
  idea is now built. `computeRelicSuggestions()` (pure, no DOM — near
  `renderProfileStories()`) groups a user's not-yet-storied Moments by area
  and time window into candidate trips, rendered as dismissible cards in a
  "Suggested relics" section above Relics on Profile
  (`renderRelicSuggestions()`, called from `buildProfile()`). Algorithm:
  find "home" as the densest ~20km grid cell of a user's Moment anchor
  points (weighted by distinct days, so one big Saturday can't outweigh
  months of routine); moments with **any** anchor more than 40km from home
  are candidate trip material (a flight's home-side anchor doesn't disqualify
  it — only its far end needs to clear the threshold, which is what lets a
  departure/return flight bridge into the trip it belongs to); union-find
  links two candidates whose nearest anchors are within 75km AND whose dates
  are within 2 days (one rest day mid-trip); groups of 2+ become a
  suggestion, titled from the most common `startPlace`/`endPlace` among the
  group or else a date-range fallback. Clicking **Create relic** opens the
  existing `openStoryModal()` pre-filled with the suggestion's Moments and
  guessed title — a suggestion is never saved on one click, the user reviews
  it first through the normal editor. **Dismiss** persists the suggestion's
  id (stable — derived from its sorted Moment ids) in
  `relic_suggest_dismissed_v1_<uid>` so it doesn't reappear on the next
  render. Moments already inside any existing Story are excluded from
  candidates. Extend `relicSuggestAnchors`/the link/gap constants at the top
  of the block, not a second grouping predicate, if this needs tuning.
  The Profile preview caps at `RELIC_SUGGEST_PREVIEW_COUNT` (3); its header's
  "Review" / "Review all N" button routes to `#relic-suggest-view` — a real
  page (`switchView('relic-suggest')` → `renderRelicSuggestView()`), not a
  modal, since the point is to actually look at what's in each suggestion,
  not glance at one in a dialog. `relicSuggestionCardHtml(s)` is the one card
  builder both the Profile preview and the full page call, so they can't
  quietly diverge; every card carries its own Moment list (name/date/type/
  distance) behind a native `<details>` disclosure — a title and date range
  alone don't say what's actually in a suggestion — using the lightweight
  `moments` array each suggestion carries for display (not full Moment
  objects). `dismissRelicSuggestion` re-renders whichever of the preview or
  the full page is on screen (checks `currentView`); `openSuggestedRelicModal`
  works the same from either.
  **Ranked, not chronological**: `relicSuggestionScore()` gives each group a
  confidence score — more activities, more days spanned, more variety of
  activity type (a flight + hikes + a run reads as a trip; five laps of the
  same park reads as routine that happens to be far from home), a resolved
  place name, and distance from home — and `computeRelicSuggestions()` sorts
  suggestions by that score, best first, rather than by date. The score is
  internal (sort order only, not shown as a number) — tune the weights in
  `relicSuggestionScore`, don't add a second ranking pass elsewhere.

## Relic glyph (`relic-glyph`, 2026-09-22)

A Story's tracks drawn as one line-drawing, used as its thumbnail. "Relic" is
the **front-end name for a Story** — the code, table, `type: 'story'`
discriminator, every identifier and CSS class stay `story`; only user-visible
copy says Relic. Don't rename the model.

- **Chains, not tracks, are the unit of normalisation.** A multi-day route
  arrives as one Moment per day, each starting where the last finished;
  normalising them separately pins every day's start on the anchor and shreds
  the route. `glyChainIds()` groups days whose endpoints meet (tolerance
  scaled to the legs, floor 0.3 km, ceiling 8 km) and the chain is fitted as
  one figure by `glyFitOriginMulti`/`glyFitIntersectMulti`, while each day
  keeps its own colour. A chain of one behaves exactly as a lone track did.
  Flights never chain — their geometry is replaced by a synthetic arc, so
  there is no real endpoint to meet. `storyGlyphTracks()` sorts by date,
  without which chaining means nothing.
- **Not a map.** Each chain is scaled *on its own* to a common size and
  stacked on a shared anchor, so the result is a mark. Tracks are **never
  rotated** — north stays up, so a glyph keeps true cardinal direction and a
  straight track stays straight at its real bearing. The user asked for this
  explicitly; don't add PCA/orientation normalisation.
- **Pipeline** (`gly*`-prefixed pure functions, near `renderShareCard`):
  cos(lat) projection → `glySimplifyTo` (RDP to a *target segment count*, not a
  fixed tolerance) → `glyQuantAngles` → fit → whole-composition fit. Quantising
  every heading drifts the endpoint and leaves loops visibly unclosed, so the
  error is spread back along the path — don't "fix" that by removing it.
- **Two families of style, and the difference is the segment budget.** The
  faithful ones (Tracks, Survey) set `ink` — a large budget spent on keeping
  the real shape. The geometric ones scale the small `glyphBudget(n)` by `det`
  into a handful of bold strokes. `maxSeg` stops one long activity eating the
  budget. If geometric glyphs look busy, lower `glyphBudget` before anything
  else; it was once ~3× higher and real relics came out as scribble.
- **Simplification destroys lap sports, so the default is faithful.** An
  alpine day is the same corridor ridden up and down a dozen times; RDP keeps
  only the extremes, so an over-simplified ski relic collapses to a line
  traced back and forth — a real user relic looked like this. Rendered
  faithfully the same relic is a legible comb of laps. The user's standing
  preference is that **glyphs should look like the tracks**, so `tracks` is
  `GLYPH_DEFAULT_STYLE`; the geometric styles are the alternative, not the
  norm.
- **Flights ignore their geometry.** Most flight data has no usable trace
  (Strava/GPX never populate `endLat`/`endPlace`; manual entry draws a straight
  line), so a flight is redrawn as a fixed-bow arc at its real bearing via
  `glyFlightArc` — every flight is the same mark differing only in heading,
  which is what makes a curve read as "flight" at 64px.
- **Styles are user-picked, not inferred.** `GLYPH_STYLES` holds five, all
  tuned and working, but only those without `wip: true` reach the picker
  (`glyphStyleKeys()`). Shipping two — **Accurate** (default) and **Runic**,
  the two ends of the abstraction axis — and releasing another is just
  deleting its flag. Held back, with reasons: `geometric` (the natural third),
  `weave` (least differentiated; reads as busier Geometric at 64px), `survey`
  (true geography, so a relic spread over a region collapses — the longest
  track dominates the shared bounds). A relic already set to a held-back style
  still renders and still lists it, so releasing one never strands a choice.
  `GLYPH_STYLE_ALIASES` maps earlier names. **The default is constant.**
  Deriving it from the tracks was tried and measured worse: an unchosen relic
  recomputes on every render, so its mark changed *kind* as the relic grew.
  A glyph is an identity; keep the default constant.
- **Colour is a separate axis** from style, with three modes: `track` (the
  user's own colours — `m.customColor || getColor(m.type)`, so
  `relic_colors_v1` overrides come through), `shade`, and `one` (a colour they
  pick). `shade` exists because same-sport tracks share a colour, so a relic
  of five runs was five identical red lines: `glyShadeColours()` groups tracks
  by resolved colour and spreads HSL lightness within each group, so different
  sports keep their hue and same-sport tracks still separate. `glyInk()`
  floors luminance and `glyShade()` caps it at 0.70, because a pale colour
  vanishes on the light card the glyph sits on. The old two-state `mono` flag
  is migrated in `glyphPrefFor`.
- **Choices live on the relic row** (`glyph_style` / `glyph_colour` /
  `glyph_ink`, see `docs/supabase-glyph.sql` — must be applied before this
  ships). `relic_glyph_v1` in localStorage is now only a *fallback*, read per
  field for choices made before the columns existed and for a relic still
  being built (`GLYPH_NEW`), which has no row. Changing the look of a shared
  relic re-pushes its snapshot (`refreshStorySnapshot`).
- **A follower's glyph must match the owner's, which `polylines` cannot do.**
  Redaction splits one track into several segments, so that array is not 1:1
  with the relic's activities and rebuilding tracks from it would normalise
  fragments. `story_public.glyph_tracks` is the glyph's own structure — one
  jsonb entry per activity in date order, `{p: [encoded…], c, k}` — where `k`
  is the TYPE_CONFIG group, without which a follower cannot tell a flight
  (an arc) from anything else. `publicGlyphSvg(row)` renders it.
- **`story_public.photos` holds storage paths, not URLs**, signed on read by
  `Social.storyPhotos()`, so nothing long-lived sits in the snapshot. Sharing
  a relic therefore shares its photos — the share confirm says so. This needs
  the **"public relic photo files"** storage policy in
  `docs/supabase-glyph.sql`: the older policy grants a signed URL only via
  `activity_public`, and a relic is usually built from private activities, so
  without it a shared relic renders no photos at all.
- Snapshot upserts use `onConflict: 'user_id,story_id'` — `story_public`'s
  primary key is the pair, and naming `story_id` alone fails with 42P10 on
  every write.
- **Every `.modal-overlay` shares `z-index: 500`, so DOM order decides.**
  `#confirm-modal` / `#form-modal` are opened *from* later modals (bulk
  editor, relic builder, share sheet) and so are pinned above them
  explicitly. A new modal that can raise a confirm must sit below that.
- Renders on the profile story card (`is-glyph`; the canvas mini-map stays as
  the fallback for a relic with no GPS) and in the detail panel as a 64px
  thumbnail top-left, with the `sd-map` hero below it placed *relative to the
  glyph at insert time* — it is built later in `showStoryDetail` than it is
  displayed.
- **The detail panel shows the glyph, it does not configure it.** Style and
  colour live behind **Edit** (the glyph block in `#story-modal`) and in the
  **Share** popup (`#relic-share-modal`), the way a Strava activity keeps its
  settings out of the view. `glyphControlsHtml()` is rendered into whichever
  of the mounts in `GLYPH_MOUNTS` exist, and `glyphRefresh()` updates them
  all — add a new mount there rather than wiring a fourth refresh path.
- **`saveStory()` rebuilds the relic object from the form**, so any field not
  restated there is dropped on every save — that is how the glyph columns and
  `isPublic` were being reset by clicking "Save Changes". Add a new relic
  field to that literal as well as to the mappers.
- A relic being built has no id, so its glyph choices are staged under
  `GLYPH_NEW` and written straight onto the object in `saveStory()` — not via
  `setGlyphPref`, which would take its localStorage branch because `db[id]`
  does not exist yet. `clearStagedGlyphPref()` runs on save *and* on
  `openStoryModal`, or a cancelled relic's look leaks into the next one.
  `glyphStoryById()` returns the staged stand-in built from
  `storySelectedIds`, which is what lets the edit modal preview a relic that
  does not exist yet.
- `glyphToBlob()` rasterises the *same* inline SVG through an `Image` rather
  than redrawing on canvas, so the shared PNG and the on-screen glyph cannot
  drift apart.

## The feed is relics only (`relic-glyph`, 2026-09-22)

**Both tabs.** `buildFollowingFeed()` reads `story_public` and nothing else,
with **keyset pagination on `(date_end, story_id)`** — `date_end` is a *date*,
so a plain `.lt(date_end, cursor)` permanently skips every other relic ending
on the same day as a page boundary. The cursor is `{d, id}`; `buildOwnFeed()` (the You tab) reads `getStories()`.
**A public activity is still public** — it shows on its owner's profile, in
the Activities view and on the friends map layer, and `Social.feed()` /
`itemFromPublicRow()` still serve those — but it is not a post. The feed is
the curated layer; individual activities live in the Activities view.

A feed card leads with the glyph (clickable, opens the relic), then title,
narrative, stats and photos. The card's own mini-map was removed: the glyph
replaced it and two maps of the same tracks was one too many. The two card
builders — `renderPublicStoryCard` (snapshot rows) and `renderFeedStoryCard`
(your own, from `db`) — must stay in step; they quietly diverged once and the
You tab kept rendering a canvas map after the shared card had moved on.

**Every empty feed state offers both roads out** — follow someone, or make
your own relic — because either one fills the feed. There are three
(`buildFollowingFeed`: following nobody, and nobody-has-shared;
`buildOwnFeed`: no relics of your own), and they differ only in which action
is primary. Don't write copy promising an action the block has no button for.

**Front-end copy says "activity", never "moment".** `Moment` stays the model
name in code (`getMoments`, `momentIds`, `moment_count`, every identifier and
CSS class); only user-visible strings changed.

Any new `Social` method needs its `DemoSocial` twin (`storyPhotos` has one),
and the `demoStories` fixture has to carry new snapshot fields or `?demo`
renders a relic card with no glyph and no photos. That fixture is built during
boot, so it cannot name consts declared further down the file — doing so
throws on the temporal dead zone and takes the whole demo seed with it.

## Relic photos (`relic-glyph`, 2026-09-22)

A relic shows every photo taken on its tracks (`storyPhotos()` gathers
`m.photos` across `momentIds`, in date order), and photos added *to the relic*
are filed onto the track they belong to rather than the relic itself — there is
no relic-level photo store, and adding one would duplicate `activity_photos`.

- **`assignPhotoToRelic(story, taken, lat, lng)` decides where a photo goes.**
  **Time is tried first and beats GPS**: a photo taken during an activity
  belongs to it, and `DateTimeOriginal` survives when location tagging is off,
  which it often is. A photo within 30 min either side of the activity window
  counts. GPS is the fallback, nearest point on any of the relic's tracks
  within 1.5 km. Neither → returns null and the caller *says so* rather than
  guessing a track.
- **Both times are compared as UTC, and that is deliberate.** An activity's
  `date` is Strava's `start_date_local` stored as a timestamptz with a `+00:00`
  offset — local wall-clock labelled UTC. EXIF `DateTimeOriginal` is also
  wall-clock with no zone, so `readExifTaken()` returns `Date.UTC(...)`.
  Reading it as browser-local instead compares the two in different frames and
  silently breaks time matching for every user outside UTC.
- **`readExifTaken()` is deliberately separate from `readEXIF()`.** The latter
  is dense, load-bearing GPS-parsing code; this only needed one more tag
  (IFD0 → Exif SubIFD `0x8769` → `0x9003`), so it walks its own copy rather
  than risking that parser. EXIF timestamps carry no zone, so it is read as
  local time — which is what a camera writes and what an activity's local
  start time is stored as.
- `uploadPhotoToMoment(memId, file, geo)` is the single place storage layout,
  the `activity_photos` row and the local `db` update happen; the Moment's own
  grid and the relic upload both call it. `geo` is passed in when the caller
  already read EXIF, so a file isn't parsed twice.

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
  map control, now a sliders icon) covering type/source/date/distance/duration/elevation/
  heart-rate/mood/attributes, **plus a "Pins" section** (added during the
  merge) driven by `PIN_CATEGORIES`/`activePinCategories` — kept structurally
  separate from `filters` since Pins aren't tracked Moments and none of the
  distance/duration/HR-style filters apply to them. Track colors moved into
  this same drawer too ("Track colours" section, still `updateTypeColor()`).
  **"Track thickness"** (2026-09-22, added after) is the same idea for line
  width: one `trackWidth` multiplier (0.5–3, slider, default 1), also *not*
  part of `filters`/`matchMoment` — it doesn't hide/show anything, so it's
  excluded from `activeFilterCount()` and `clearFilters()`, same precedent
  as Track colours. It persists in `relic_mapprefs_v1_<uid>` alongside
  `filters`/`sidebarSort` (see `saveMapPrefs()`/`applyStoredFilters()`), and
  is read back **before** `initMapLayers()` first creates the layers so a
  returning user's saved thickness applies to the very first paint, not just
  after their next interaction. `setTrackWidth()` → `applyTrackThickness()`
  scale `tracks-layer`, `tracks-highlight`, and `friends-layer` together;
  `tracks-layer`'s width lives in one of three *shapes* depending on what's
  currently open — nothing (`tracksLineWidthExpr()`, zoom-interpolated),
  one Moment (`updateTrackHighlight()`'s `['case',...]`), or a Story
  (`viewStoryOnMap()`'s own `['any',...]` case, never routed through
  `updateTrackHighlight()`) — and `applyTrackThickness()` re-derives
  whichever one currently applies rather than assuming the Moment-or-nothing
  shape, which would otherwise silently cancel a live Story highlight back
  to the untouched-map default the moment someone nudged the slider. The
  invisible hit-testing layers (`tracks-hit`, `friends-hit`, `draw-route-
  hit`) and the draw-route tool's own line are deliberately **not** scaled —
  different concerns (a bigger tap target; a temporary drawing aid), not
  "how thick do my tracks look."
- **Activities view** (`#activities-view`, `renderActivitiesView()`) is a
  sortable table reachable from the header nav (desktop) / mobile hamburger
  menu, and since 2026-09-20 also from the account-avatar dropdown
  (`#account-menu`, "Your activities") — see "Profile = Stories only" above.
  Shares `filteredMemories` with the map. The old Archive/stats page
  (`buildStats()`, `#stats-view`) is **parked** — code kept, not reachable
  from nav — per `map-filters`' original design, not something this merge
  changed.
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

**Entry point**: a single "+ Add" button (header on desktop, the centre + of the mobile tab bar) opens
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
