/*
  Relic - glyph appearance + relic photos in the public snapshot
  (relic-glyph branch, 2026-09-22)

  Deliberately ASCII-only, with block comments instead of "dash dash" line
  comments: editors and chat clients that apply smart punctuation turn two
  hyphens into an en dash, which stops the line being a comment at all and
  makes Postgres try to execute the prose. Keep it that way.

  Two gaps this closes, both with the same cause: everything about how a
  relic looks was owner-only, so a follower opening a shared relic saw a
  default-styled glyph and none of its photos.

    glyph_style / glyph_colour / glyph_ink
      The chosen glyph style ('accurate', 'runic', ...), colour mode
      ('track' | 'shade' | 'one') and, for the one-colour mode, the hex
      picked. Nullable: null means "not chosen" and the client falls back to
      the constant default, so no backfill is needed.

    glyph_tracks (story_public only)
      What the glyph needs and the existing polylines array cannot give:
      privacy redaction splits one track into several segments, so polylines
      is not 1:1 with the relic's activities, and a follower rebuilding
      tracks from it would normalise fragments instead of tracks - a
      different drawing from the owner's. One jsonb entry per activity, in
      date order:
        { p: [encoded polyline, ...], c: '#rrggbb', k: 'Flight' | 'Run' | ... }
      k is the TYPE_CONFIG group, without which a follower cannot tell a
      flight (drawn as an arc) from anything else.

    photos (story_public only)
      Storage paths of the photos taken on the relic's tracks, so a follower
      can see them without reading the owner's activity_photos rows. Paths,
      not URLs - the reader signs them, so nothing long-lived sits in the
      snapshot.

  MUST run before the matching index.html is deployed: storyToRow() sends the
  three glyph columns and buildStorySnapshotRow() sends all four, and an
  upsert naming a column that does not exist fails - which would make every
  relic save fail. Idempotent; safe to re-run.
*/

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

/*
  Guard against a bad client writing a colour mode the renderer does not
  know. The client normalises too; this is the backstop.
*/

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

/*
  Photo files inside a shared relic.

  The existing "public activity photo files" policy grants a signed URL only
  for photos whose activity has an activity_public row. A relic is very often
  built from private activities, so without this a shared relic shows no
  photos at all - while the share confirmation promises them.

  Scoped to exactly the paths the owner published in story_public.photos:
  sharing a relic exposes its photos, and nothing else.
*/

drop policy if exists "public relic photo files" on storage.objects;

create policy "public relic photo files" on storage.objects for select to authenticated using (
  bucket_id = 'photos'
  and exists (
    select 1 from public.story_public sp
    where storage.objects.name = any (sp.photos)
  )
);
