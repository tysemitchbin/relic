-- Relic — glyph appearance + relic photos in the public snapshot
-- (relic-glyph branch, 2026-09-22)
--
-- Two gaps this closes, both with the same cause: everything about how a
-- relic looks was owner-only, so a follower opening a shared relic saw a
-- default-styled glyph and none of its photos.
--
--   glyph_style / glyph_colour / glyph_ink
--     The user's chosen glyph style ('accurate', 'runic', …), colour mode
--     ('track' | 'shade' | 'one') and, for the one-colour mode, the hex they
--     picked. Nullable: null means "not chosen", and the client falls back to
--     the constant default rather than needing a backfill.
--
--   glyph_tracks (story_public only)
--     What the glyph needs, which the existing `polylines` array cannot give:
--     redaction splits one track into several segments, so polylines is not
--     1:1 with the relic's activities, and a follower rebuilding tracks from
--     it would normalise fragments instead of tracks — a different drawing
--     from the owner's. One jsonb entry per activity, in date order:
--       { p: [encoded polyline, …], c: '#rrggbb', k: 'Flight' | 'Run' | … }
--     `k` is the TYPE_CONFIG group, without which a follower cannot tell a
--     flight (drawn as an arc) from anything else.
--
--   photos (story_public only)
--     Storage paths of the photos taken on the relic's tracks, so a follower
--     can see them without being able to read the owner's activity_photos
--     rows. Paths, not URLs — the reader signs them, so nothing long-lived
--     leaks into the snapshot.
--
-- MUST run before the matching index.html is deployed: storyToRow() now sends
-- the three glyph columns and buildStorySnapshotRow() sends all four, and an
-- upsert naming a column that doesn't exist fails — which would make every
-- relic save fail. Idempotent; safe to re-run.

alter table public.stories
  add column if not exists glyph_style  text,
  add column if not exists glyph_colour text,
  add column if not exists glyph_ink    text;

alter table public.story_public
  add column if not exists glyph_style  text,
  add column if not exists glyph_colour text,
  add column if not exists glyph_ink    text,
  add column if not exists glyph_tracks jsonb  not null default '[]'::jsonb,
  add column if not exists photos       text[] not null default '{}';

-- Guard against a bad client writing a mode the renderer doesn't know; the
-- client also normalises, this is the backstop.
alter table public.stories
  drop constraint if exists stories_glyph_colour_check;
alter table public.stories
  add constraint stories_glyph_colour_check
  check (glyph_colour is null or glyph_colour in ('track', 'shade', 'one'));

alter table public.story_public
  drop constraint if exists story_public_glyph_colour_check;
alter table public.story_public
  add constraint story_public_glyph_colour_check
  check (glyph_colour is null or glyph_colour in ('track', 'shade', 'one'));
