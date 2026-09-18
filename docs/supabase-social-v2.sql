-- Relic — Social v2: kudos, comments, public stories, and a fix for photos on public profiles.
-- Run in the Supabase SQL Editor AFTER supabase-social.sql and
-- supabase-privacy-radius.sql. Safe to re-run (idempotent).
--
-- The app works without this file: kudos/comment buttons just stay hidden
-- until these tables exist (the client detects "relation does not exist").
--
-- Notifications need no table of their own: the client derives them from
-- follows (followee_id = me), kudos (activity_user_id = me) and comments
-- (activity_user_id = me), newest first, and remembers a per-device
-- "last seen" timestamp. Add a real notifications table + trigger later if
-- you want push/email delivery.

-- ── 1. Kudos (one per person per activity) ──────────────────────────────
create table if not exists public.kudos (
  activity_user_id uuid not null,
  activity_id      text not null,
  user_id          uuid not null default auth.uid() references auth.users on delete cascade,
  created_at       timestamptz not null default now(),
  primary key (activity_user_id, activity_id, user_id),
  foreign key (activity_user_id, activity_id) references public.activities (user_id, id) on delete cascade
);
create index if not exists kudos_owner_idx on public.kudos (activity_user_id, created_at desc);
alter table public.kudos enable row level security;

drop policy if exists "read kudos" on public.kudos;
create policy "read kudos" on public.kudos for select to authenticated using (
  user_id = auth.uid()
  or activity_user_id = auth.uid()
  or exists (select 1 from public.activity_public p
             where p.user_id = kudos.activity_user_id and p.activity_id = kudos.activity_id)
);
drop policy if exists "give kudos" on public.kudos;
create policy "give kudos" on public.kudos for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.activity_public p
              where p.user_id = kudos.activity_user_id and p.activity_id = kudos.activity_id)
);
drop policy if exists "take back kudos" on public.kudos;
create policy "take back kudos" on public.kudos for delete to authenticated using (user_id = auth.uid());

-- ── 2. Comments ─────────────────────────────────────────────────────────
create table if not exists public.comments (
  id               uuid primary key default gen_random_uuid(),
  activity_user_id uuid not null,
  activity_id      text not null,
  user_id          uuid not null default auth.uid() references auth.users on delete cascade,
  body             text not null check (char_length(body) between 1 and 1000),
  created_at       timestamptz not null default now(),
  foreign key (activity_user_id, activity_id) references public.activities (user_id, id) on delete cascade
);
create index if not exists comments_activity_idx on public.comments (activity_user_id, activity_id, created_at);
create index if not exists comments_owner_idx on public.comments (activity_user_id, created_at desc);
alter table public.comments enable row level security;

drop policy if exists "read comments" on public.comments;
create policy "read comments" on public.comments for select to authenticated using (
  user_id = auth.uid()
  or activity_user_id = auth.uid()
  or exists (select 1 from public.activity_public p
             where p.user_id = comments.activity_user_id and p.activity_id = comments.activity_id)
);
drop policy if exists "write comments" on public.comments;
create policy "write comments" on public.comments for insert to authenticated with check (
  user_id = auth.uid()
  and exists (select 1 from public.activity_public p
              where p.user_id = comments.activity_user_id and p.activity_id = comments.activity_id)
);
-- You can delete your own comments, and any comment on your own activity.
drop policy if exists "delete comments" on public.comments;
create policy "delete comments" on public.comments for delete to authenticated using (
  user_id = auth.uid() or activity_user_id = auth.uid()
);

-- ── 3. FIX: photos on public activities were invisible to everyone else ──
-- The old policies checked `activities.is_public` via a subquery, but RLS
-- also applies inside policy subqueries, and non-owners can no longer read
-- `activities` at all (supabase-privacy-radius.sql dropped that policy). So
-- the subquery always came back empty for anyone but the owner. Check the
-- readable `activity_public` snapshot table instead.
drop policy if exists "public activity photos" on public.activity_photos;
create policy "public activity photos" on public.activity_photos for select to authenticated using (
  exists (select 1 from public.activity_public p
          where p.user_id = activity_photos.user_id and p.activity_id = activity_photos.activity_id)
);
drop policy if exists "public activity photo files" on storage.objects;
create policy "public activity photo files" on storage.objects for select to authenticated using (
  bucket_id = 'photos'
  and exists (
    select 1 from public.activity_photos ph
    join public.activity_public p on p.user_id = ph.user_id and p.activity_id = ph.activity_id
    where ph.storage_path = storage.objects.name
  )
);

-- ── 4. Helpful indexes for the feed / suggestions queries ────────────────
create index if not exists activity_public_user_date_idx on public.activity_public (user_id, date desc);
create index if not exists activity_public_updated_idx on public.activity_public (updated_at desc);
create index if not exists follows_followee_idx on public.follows (followee_id);

-- ── 5. OPTIONAL: stop the anonymous role reading the social graph ────────
-- `follows`, `profiles` and `activity_public` currently have select policies
-- with no `to authenticated`, so anyone holding the (public) publishable key
-- can read them without signing in. Signed-out *profile previews* from invite
-- links use `profiles` (name + avatar), so leave that one open; `follows`
-- probably doesn't need to be public:
--
-- drop policy if exists "read follows" on public.follows;
-- create policy "read follows" on public.follows for select to authenticated using (true);

-- ── 6. Public Stories ────────────────────────────────────────────────
-- Same pattern as activity_public: a redacted snapshot written by the
-- owner's own client (tracks trimmed by each moment's privacy radius, or
-- 500 m when it has none), readable by any signed-in user. A row exists only
-- while the story is shared; "is this story public?" = "does a row exist?",
-- so the stories table itself needs no new column.
create table if not exists public.story_public (
  user_id      uuid not null references auth.users on delete cascade,
  story_id     text not null,
  title        text not null default 'Untitled',
  narrative    text not null default '',
  mood         text,
  date_start   date,
  date_end     date,
  moment_count integer not null default 0,
  distance     double precision not null default 0,
  duration     double precision not null default 0,
  elevation    double precision not null default 0,
  type_counts  jsonb not null default '{}'::jsonb,
  polylines    text[] not null default '{}',
  colors       text[] not null default '{}',
  updated_at   timestamptz not null default now(),
  primary key (user_id, story_id),
  foreign key (user_id, story_id) references public.stories (user_id, id) on delete cascade
);
create index if not exists story_public_user_date_idx on public.story_public (user_id, date_end desc);
alter table public.story_public enable row level security;
drop policy if exists "own public story snapshot" on public.story_public;
create policy "own public story snapshot" on public.story_public
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "read public story snapshot" on public.story_public;
create policy "read public story snapshot" on public.story_public for select to authenticated using (true);
