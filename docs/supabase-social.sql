-- Relic — Social features (search, follow, public activities)
-- Run in the Supabase SQL Editor after supabase-schema.sql.

-- ── is_public on activities ──
-- NOTE: an earlier version of this file also added a
-- `create policy "public activities" ... for select using (is_public = true)`
-- policy directly on activities. That's since been removed (see
-- docs/supabase-privacy-radius.sql) -- Postgres RLS is row-level, not
-- column-level, so that policy exposed the raw polyline/start_lat/start_lng
-- of every public activity to any signed-in user, with no way to redact
-- privacy-radius'd coordinates out of it. Non-owners now read exclusively
-- from activity_public, which only ever contains what the owner's own
-- client explicitly published there.
alter table public.activities add column if not exists is_public boolean not null default false;

-- ── private per-activity note — its own table, ALWAYS owner-only RLS, no
-- exceptions. Kept separate from activities on purpose: Postgres RLS is
-- row-level, not column-level, so a column on a table that's partly public
-- can't be redacted per-viewer. Splitting it into its own table is what
-- makes opening up SELECT on activities.is_public safe.
create table if not exists public.activity_private_notes (
  user_id     uuid not null references auth.users on delete cascade,
  activity_id text not null,
  note        text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (user_id, activity_id),
  foreign key (user_id, activity_id) references public.activities (user_id, id) on delete cascade
);
alter table public.activity_private_notes enable row level security;
create policy "own private notes" on public.activity_private_notes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── public read of photos belonging to a public activity (additive) ──
create policy "public activity photos" on public.activity_photos for select
  using (exists (
    select 1 from public.activities a
    where a.user_id = activity_photos.user_id and a.id = activity_photos.activity_id and a.is_public
  ));

-- ── public read of the underlying storage objects for those same photos (additive) ──
create policy "public activity photo files" on storage.objects for select
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.activity_photos p
      join public.activities a on a.user_id = p.user_id and a.id = p.activity_id
      where p.storage_path = storage.objects.name and a.is_public
    )
  );

-- ── profiles: any signed-in user can read (search + viewing other profiles).
-- Writes stay owner-only via the existing "own profile" policy.
-- Note: this makes every existing user's name/bio/avatar readable by any
-- signed-in user going forward, not just the profile's own owner.
create policy "read any profile" on public.profiles for select using (true);

-- profiles are already readable by any signed-in user; extend that to the
-- avatar image itself so search results / follow lists can render it.
create policy "read avatar files" on storage.objects for select
  using (
    bucket_id = 'photos'
    and exists (select 1 from public.profiles p where p.avatar_path = storage.objects.name)
  );

-- ── follows ──
create table if not exists public.follows (
  follower_id uuid not null references auth.users on delete cascade,
  followee_id uuid not null references auth.users on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
alter table public.follows enable row level security;
create policy "read follows" on public.follows for select using (true);
create policy "create own follows" on public.follows for insert with check (follower_id = auth.uid());
create policy "delete own follows" on public.follows for delete using (follower_id = auth.uid());
