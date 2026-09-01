# Relic — feature wishlist

Things we want to build later. Not bugs (those get fixed as they come up) —
this is the "someday / next" list. Add freely; prune when shipped.

## Next up

- **Visual redesign pass** — rethink the look of the feed cards, Archive, and
  Profile: colour, typography, layout. (Mobile layout is done; this is styling.)
- **Beta feedback: run the migration** — `docs/supabase-feedback.sql` needs to be
  run once in the Supabase SQL Editor before the in-app Feedback button works.

## Polish

- **Naming consistency** — the per-activity write-up field is called "Story" in the
  detail panel, "Notes" on Profile, and "Written Memories" on Archive. Pick one
  ("Note" for the per-activity text; reserve "Story" for the multi-moment
  collections) and use it everywhere.
- **Feedback modal: attach a screenshot** — deferred from the first pass; would
  make bug reports far more useful.
- **Static map on the Story detail view** — feed + profile story cards now show
  real Mapbox tiles behind the tracks; the story detail panel still doesn't.

## Dopamine / delight

Gamified, rewarding moments — make opening the app feel good.

- **First-connect "big reveal"** — when a new user connects Strava, don't draw
  tracks as they trickle in. Hold them all, show a syncing counter that ticks up
  ("1,204 activities… 87,000 km…") to build anticipation, then animate the whole
  archive onto the map at once — fade/draw-on, fly-to-fit-bounds.
- **Autoframe to the most recent activity** — on load, ease the map to frame the
  newest track instead of the default world view.
- **"% new ground" on a new activity** — after a sync, tell the user how much of
  each new activity covered places they'd never been (compare its coords against
  all prior tracks). Turns exploring new routes into a score.
- **"On this day"** — surprise pop-up surfacing an activity from this calendar
  date in a previous year.
- **Personal records as trophies on the map** — plot PRs (fastest 5k, longest
  ride, biggest climb, etc.) as emoji/trophy markers at the spot they happened.

## Interaction

- **Easier to click tracks** — widen the hit target on the tracks layer (invisible
  fat line under the visible one, or a click-nearest-track fallback) so you don't
  have to land exactly on a 2px line.
- **Quick fly-in on activity click** — a snappy camera move when a track is
  selected (short duration, ease into a tight fit-bounds), so selecting feels
  responsive rather than a slow pan.

## Social / sharing

- **Trips are the shareable unit, not tracks** — a raw activity isn't a "post".
  The thing you share / that shows in a feed is a Trip (a grouped set of
  activities — same idea as Stories). Reframe the feed and sharing around trips.
- **Co-owned tracks** — if two people did an activity together, both can claim
  it; it appears in both archives and links the two accounts on that track.
- **Shareable recap cards** — generate a polished image card (à la Strava /
  Spotify Wrapped) for a trip, a year, or a milestone, sized for sharing.

## AI

- **AI-suggested stories** — cluster moments into proposed Stories automatically
  and name them ("Dog walks this week", "Norway road trip"), one tap to accept.

## Investigate

- **272 "notes"** — the archive shows 272 activities with note text, but those
  weren't typed by hand. Find where they came from (v1 migration? bulk import?)
  and decide whether to keep / clear / relabel them.

## Later / maybe

- (add ideas here)
