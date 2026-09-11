-- Relic — Supabase schema + RLS + storage policy
-- Run in the Supabase SQL Editor. Create the private storage bucket `photos`
-- in the dashboard BEFORE running the storage policy at the bottom.

-- ── PROFILES ──────────────────────────────────────────────
create table public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  name        text not null default '',
  bio         text not null default '',
  avatar_path text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Auto-create a profile row when a user signs up
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── ACTIVITIES (moments) ──────────────────────────────────
create table public.activities (
  id                text        not null,
  user_id           uuid        not null references auth.users on delete cascade,
  name              text        not null default 'Untitled',
  type              text        not null default 'Other',
  date              timestamptz,
  source            text,                       -- strava | import | kml_import | manual
  strava_id         bigint,
  distance          double precision not null default 0,
  duration          double precision not null default 0,
  elevation         double precision not null default 0,
  polyline          text,                       -- encoded polyline
  start_lat         double precision,
  start_lng         double precision,
  note              text        not null default '',
  mood              text,
  is_public         boolean     not null default false,
  custom_color      text,
  name_edited       boolean     not null default false,
  -- Strava returns several of these as decimals, so keep them floating-point
  avg_hr            double precision,
  max_hr            double precision,
  calories          double precision,
  avg_speed         double precision,
  max_speed         double precision,
  avg_cadence       double precision,
  avg_watts         double precision,
  weighted_watts    double precision,
  suffer_score      double precision,
  pr_count          integer,
  achievement_count integer,
  elev_high         double precision,
  elev_low          double precision,
  gear_id           text,
  workout_type      integer,
  commute           boolean     not null default false,
  elapsed_time      double precision,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (user_id, id)
);
create index activities_user_date_idx on public.activities (user_id, date desc);

-- ── STORIES ───────────────────────────────────────────────
create table public.stories (
  id               text        not null,
  user_id          uuid        not null references auth.users on delete cascade,
  title            text        not null default 'Untitled',
  narrative        text        not null default '',
  mood             text,
  cover_photo_path text,
  moment_ids       text[]      not null default '{}',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  primary key (user_id, id)
);

-- ── ACTIVITY PHOTOS ───────────────────────────────────────
create table public.activity_photos (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users on delete cascade,
  activity_id  text        not null,
  storage_path text        not null,
  lat          double precision,
  lng          double precision,
  caption      text        not null default '',
  taken_at     timestamptz,
  sort_order   integer     not null default 0,
  created_at   timestamptz not null default now()
);
create index activity_photos_user_activity_idx
  on public.activity_photos (user_id, activity_id);

-- ── ROW-LEVEL SECURITY ────────────────────────────────────
alter table public.profiles        enable row level security;
alter table public.activities      enable row level security;
alter table public.stories         enable row level security;
alter table public.activity_photos enable row level security;

create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
create policy "read any profile" on public.profiles for select using (true);
create policy "own activities" on public.activities
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "public activities" on public.activities for select using (is_public = true);
create policy "own stories" on public.stories
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own photos" on public.activity_photos
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "public activity photos" on public.activity_photos for select
  using (exists (
    select 1 from public.activities a
    where a.user_id = activity_photos.user_id and a.id = activity_photos.activity_id and a.is_public
  ));

-- ── updated_at triggers ───────────────────────────────────
create function public.touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger t_activities_touch before update on public.activities
  for each row execute function public.touch_updated_at();
create trigger t_stories_touch before update on public.stories
  for each row execute function public.touch_updated_at();
create trigger t_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ── STORAGE: photos bucket policy ─────────────────────────
-- Create the private bucket `photos` in the dashboard first.
create policy "own photo files" on storage.objects
  for all
  using   (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "public activity photo files" on storage.objects for select
  using (
    bucket_id = 'photos'
    and exists (
      select 1 from public.activity_photos p
      join public.activities a on a.user_id = p.user_id and a.id = p.activity_id
      where p.storage_path = storage.objects.name and a.is_public
    )
  );
create policy "read avatar files" on storage.objects for select
  using (
    bucket_id = 'photos'
    and exists (select 1 from public.profiles p where p.avatar_path = storage.objects.name)
  );

-- ── STRAVA CONNECTIONS (Phase 6) ──────────────────────────
-- Also in docs/supabase-strava.sql for running standalone on an existing project.
-- strava_connections + the strava_upsert_activities() merge helper:
-- full definitions in docs/supabase-strava.sql (kept there so it can be run
-- standalone on an existing project). Run that file after this one.
create table if not exists public.strava_connections (
  user_id         uuid primary key references auth.users on delete cascade,
  athlete_id      bigint,
  access_token    text not null,
  refresh_token   text not null,
  expires_at      bigint not null,
  scope           text,
  athlete         jsonb,
  synced_at       timestamptz,
  first_sync_done boolean not null default false,
  sync_page       integer not null default 1,
  connected_at    timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
-- RLS on, NO policy: only the `strava` Edge Function (service role) touches this.
alter table public.strava_connections enable row level security;

-- ── BETA FEEDBACK ─────────────────────────────────────────
-- Also in docs/supabase-feedback.sql for running standalone on an existing project.
create table if not exists public.feedback (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users on delete cascade,
  email           text,
  message         text not null,
  context         text,
  user_agent      text,
  screenshot_path text,                       -- path in the `photos` bucket, `<user_id>/feedback/<uuid>.jpg`
  created_at      timestamptz not null default now()
);
create index if not exists feedback_user_created_idx
  on public.feedback (user_id, created_at desc);
alter table public.feedback enable row level security;
create policy "own feedback" on public.feedback
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── SOCIAL: private notes + follows ───────────────────────
-- Also in docs/supabase-social.sql for running standalone on an existing project.
-- Private per-activity note — its own table, ALWAYS owner-only RLS, no
-- exceptions. Kept separate from activities on purpose: Postgres RLS is
-- row-level, not column-level, so a column on a table that's partly public
-- (activities.is_public above) can't be redacted per-viewer.
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
