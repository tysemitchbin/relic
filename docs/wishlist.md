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

## Investigate

- **272 "notes"** — the archive shows 272 activities with note text, but those
  weren't typed by hand. Find where they came from (v1 migration? bulk import?)
  and decide whether to keep / clear / relabel them.

## Later / maybe

- (add ideas here)
