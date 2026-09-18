-- Relic — Per-activity privacy radius
-- Run in the Supabase SQL Editor after supabase-social.sql.
--
-- Hides the track within a user-chosen radius of an activity's own start
-- and end point (e.g. home) from anyone but the owner. This has to be real
-- redaction, not a cosmetic map overlay: Postgres RLS is row-level, not
-- column-level, so once a non-owner can SELECT a row at all they can read
-- every column in it -- including the raw polyline -- regardless of what
-- the app's UI draws on top. So the redaction happens client-side, on the
-- owner's own device, before anything is written anywhere a non-owner can
-- read it.

-- Per-activity radius, meters (0 = disabled). The km/mi toggle in the UI is
-- purely a display concern.
alter table public.activities add column if not exists privacy_radius_m double precision not null default 0;

-- The ONLY thing a non-owner can ever read for someone else's activity.
-- Populated by the owner's own client whenever the activity (or its
-- privacy radius, or its public/private flag) changes, with any track
-- points within privacy_radius_m of that activity's own start/end already
-- stripped out and the remaining track split into whatever segments are
-- left. A row here exists only for activities currently marked public --
-- toggling an activity private deletes its row.
create table if not exists public.activity_public (
  user_id      uuid not null references auth.users on delete cascade,
  activity_id  text not null,
  name         text not null default 'Untitled',
  type         text not null default 'Other',
  date         timestamptz,
  distance     double precision not null default 0,
  duration     double precision not null default 0,
  elevation    double precision not null default 0,
  note         text not null default '',
  mood         text,
  custom_color text,
  polylines    text[] not null default '{}',
  updated_at   timestamptz not null default now(),
  primary key (user_id, activity_id),
  foreign key (user_id, activity_id) references public.activities (user_id, id) on delete cascade
);
alter table public.activity_public enable row level security;
create policy "own public activity snapshot" on public.activity_public
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "read public activity snapshot" on public.activity_public for select using (true);

-- Raw activities are no longer exposed to non-owners at all. If you ran
-- docs/supabase-social.sql before this file existed, drop the policy it
-- created (safe to run even if it's already gone):
drop policy if exists "public activities" on public.activities;
