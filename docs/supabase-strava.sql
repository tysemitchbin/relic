-- Relic — Strava connector (Phase 6)
-- Run in the Supabase SQL Editor. Idempotent — safe to re-run.

-- ── connection + sync state ───────────────────────────────
create table if not exists public.strava_connections (
  user_id        uuid primary key references auth.users on delete cascade,
  athlete_id     bigint,
  access_token   text not null,
  refresh_token  text not null,
  expires_at     bigint not null,          -- unix seconds
  scope          text,
  athlete        jsonb,                    -- cached Strava athlete summary
  synced_at      timestamptz,              -- last completed sync
  first_sync_done boolean not null default false,
  sync_page      integer not null default 1, -- resume cursor for the first sync
  connected_at   timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.strava_connections add column if not exists synced_at timestamptz;
alter table public.strava_connections add column if not exists first_sync_done boolean not null default false;
alter table public.strava_connections add column if not exists sync_page integer not null default 1;

-- RLS on, NO policy: holds Strava tokens; only the `strava` Edge Function
-- (service role) touches it. The browser gets state via the function's `status`.
alter table public.strava_connections enable row level security;

-- ── merge helper ──────────────────────────────────────────
-- Upserts Strava activities without clobbering the user's own edits:
-- note / mood / custom_color are never touched; a user-renamed title
-- (name_edited = true) is kept; a missing polyline / calories / suffer_score /
-- elev_high|low keeps whatever was there. Runs as the caller — RLS on
-- public.activities still applies (with check user_id = auth.uid()).
create or replace function public.strava_upsert_activities(p_rows jsonb)
returns integer
language plpgsql
as $$
declare n integer;
begin
  insert into public.activities (
    id, user_id, name, type, date, source, strava_id, polyline,
    distance, duration, elevation, start_lat, start_lng,
    avg_hr, max_hr, calories, avg_speed, max_speed, avg_cadence,
    avg_watts, weighted_watts, suffer_score, pr_count, achievement_count,
    elev_high, elev_low, gear_id, workout_type, commute, elapsed_time
  )
  select
    r->>'id', (r->>'user_id')::uuid, coalesce(r->>'name','Untitled'),
    coalesce(r->>'type','Other'), nullif(r->>'date','')::timestamptz, 'strava',
    (r->>'strava_id')::bigint, r->>'polyline',
    coalesce((r->>'distance')::double precision, 0),
    coalesce((r->>'duration')::double precision, 0),
    coalesce((r->>'elevation')::double precision, 0),
    (r->>'start_lat')::double precision, (r->>'start_lng')::double precision,
    (r->>'avg_hr')::double precision, (r->>'max_hr')::double precision,
    (r->>'calories')::double precision, (r->>'avg_speed')::double precision,
    (r->>'max_speed')::double precision, (r->>'avg_cadence')::double precision,
    (r->>'avg_watts')::double precision, (r->>'weighted_watts')::double precision,
    (r->>'suffer_score')::double precision, (r->>'pr_count')::integer,
    (r->>'achievement_count')::integer, (r->>'elev_high')::double precision,
    (r->>'elev_low')::double precision, r->>'gear_id',
    (r->>'workout_type')::integer, coalesce((r->>'commute')::boolean, false),
    (r->>'elapsed_time')::double precision
  from jsonb_array_elements(p_rows) as r
  on conflict (user_id, id) do update set
    name           = case when public.activities.name_edited
                          then public.activities.name else excluded.name end,
    type           = excluded.type,
    date           = excluded.date,
    strava_id      = excluded.strava_id,
    polyline       = coalesce(excluded.polyline, public.activities.polyline),
    distance       = excluded.distance,
    duration       = excluded.duration,
    elevation      = excluded.elevation,
    start_lat      = excluded.start_lat,
    start_lng      = excluded.start_lng,
    avg_hr         = excluded.avg_hr,
    max_hr         = excluded.max_hr,
    calories       = coalesce(excluded.calories, public.activities.calories),
    avg_speed      = excluded.avg_speed,
    max_speed      = excluded.max_speed,
    avg_cadence    = excluded.avg_cadence,
    avg_watts      = excluded.avg_watts,
    weighted_watts = excluded.weighted_watts,
    suffer_score   = coalesce(excluded.suffer_score, public.activities.suffer_score),
    pr_count       = excluded.pr_count,
    achievement_count = excluded.achievement_count,
    elev_high      = coalesce(excluded.elev_high, public.activities.elev_high),
    elev_low       = coalesce(excluded.elev_low, public.activities.elev_low),
    gear_id        = excluded.gear_id,
    workout_type   = excluded.workout_type,
    commute        = excluded.commute,
    elapsed_time   = excluded.elapsed_time;
  get diagnostics n = row_count;
  return n;
end $$;
