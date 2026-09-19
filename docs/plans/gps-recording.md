# Plan — GPS recording in a native app

**Status: Phases 0 and 1 done in code** (branch `travel-modes`, 2026-09-19): the
pending SQL was already live, the `end_lat` bug is fixed, and travel modes plus
all GPS-shaped Strava sports are grouped. Still to do for Phase 0: deploy the
`strava` edge function (it now stores `sport_type`), and the beta itself.
Phases 2–3 are not started. Decisions agreed with the user on 2026-09-19.

## What it is

Relic records **the trips Strava doesn't**: notable drives, trains, buses,
ferries, travel days. Strava stays the source for workouts.

- **The user starts and stops each recording.** Relic never tracks in the
  background on its own. People record the trips worth keeping, not every
  movement. (Passive all-day tracking was considered and **rejected** — don't
  bring it back without asking.)
- **Each recording has a battery level** the user picks, and can change
  mid-recording.
- **One recording becomes one Moment**, using the existing model (`polyline`,
  `startPlace`/`endPlace`, Stories via `momentIds`).

### Explicitly not in scope

- Passive or automatic tracking, and the "Always" location permission
- Automatic detection of the travel mode (the user picks it)
- Automatic splitting into trips and stops, and a review inbox
- Recording flights with GPS (plain-English trip entry and the IATA table
  already handle flights better)

## Battery levels

| Level | Good for | Roughly |
|---|---|---|
| **High detail** | Scenic drives, mountain passes, walks | Best GPS, a point every few metres |
| **Balanced** (default) | Most drives, bus rides | A point every ~25–50 m |
| **Battery saver** | Long train, ferry and travel days | A point every few hundred metres |

Show relative battery use ("Low / Medium / High"), not a percentage, because
real drain varies a lot between phones.

## Phases

### Phase 0 — Beta on what exists (no native app)

Get 10–30 real users on the web app: Strava/GPX import, pins, manual entry,
trip descriptions, social. Use PostHog to see whether they return weekly.
If people won't bring in their Strava history, they won't record trips either.

Housekeeping before the beta:
- Run the pending SQL (`docs/supabase-social-v2.sql`, the feedback table) in
  production.
- Fix `momentToRow`: `end_lat`/`end_lng` appear twice, so the second pair
  (`m.endLat ?? null`) overwrites the value taken from the track. Imported
  Strava/GPX tracks therefore save their end coordinates as null.

### Phase 1 — Travel modes (web change, useful straight away)

- Add the new modes to `TYPE_CONFIG` (e.g. Train, Bus, Ferry, others).
  **The user decides the list**, as with `PIN_CATEGORIES`. Drive, Walk and
  Flight already exist.
- Colours, icons, filter-drawer entries, and the manual-entry and
  trip-description mode pickers.
- Manual entries and trip descriptions can use the new modes before any
  native work.

### Phase 2 — Native shell (Capacitor)

Wrap the existing `index.html`. Nothing records yet; the goal is the web app
running properly as an iOS/Android app.

- **Mapbox token:** the current one is restricted to our URLs. The app's
  origin is `capacitor://localhost` (iOS) or `https://localhost` (Android), so
  it needs its own token.
- **Auth redirects:** email confirmation and password reset must open the app
  (universal links / app links, or a custom URL scheme) and be added to the
  Supabase redirect allowlist.
- **Deep links:** `?u=` / `&a=` / `&s=` need the same treatment.
- **Updates and versioning:**
  - database changes that don't break older app versions still on phones
  - a minimum-version check ("please update")
  - ideally a live-update service (Capgo/Appflow) so the web part updates
    without a store release
- **A staging Supabase project** for beta builds.
- **Native crash reporting** (e.g. Sentry).
- **Builds:** Android on Windows with Android Studio. iOS through a cloud Mac
  (Codemagic / GitHub Actions).
- **Store accounts:** Apple Developer ($99/yr) → TestFlight; Google Play
  ($25 one-time) → internal testing.
- **`privacy.html`:** add a section on location recording.

### Phase 3 — Recording

1. **Permissions:** "While Using" plus background mode on iOS; a foreground
   service with a "Recording…" notification on Android. No "Always" prompt.
2. **Plugin:** start with `@capacitor-community/background-geolocation`.
   First check that it lets us set accuracy and update frequency, because the
   battery levels depend on it. If it doesn't, use Transistor's plugin or a
   small custom one.
3. **Recording screen:** Start → pick mode and battery level → live line on
   the map, elapsed time and distance, level switch, pause and stop.
4. **Recording that survives problems:** save every point to the phone as it
   arrives (IndexedDB / SQLite). A recording must survive the app being
   killed, the phone restarting, or having no signal. On relaunch, offer to
   resume or finish an unfinished recording.
5. **Finish screen:**
   - name, mode, trim start and end
   - private by default, with the privacy radius
   - add to a Story
   - reuse the manual-entry and draw-route screens and patterns
6. **Upload:** save the Moment through the usual save sequence
   (`persistMoments`). If it's offline, queue and retry, and keep the local
   copy until the upload is confirmed.
7. **Strava overlap:** if a recording overlaps a Strava activity in time,
   show a warning. No automatic merging.

### Later (not planned yet)

- Removing GPS spikes, and splitting or merging recordings
- Suggesting a pin when a recording pauses somewhere for a long time
- "Landed at X, add your flight?"
- A recording widget or shortcut on the lock screen
