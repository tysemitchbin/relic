-- Relic — user-editable activity date/time (relic-suggestions branch, 2026-09-23)
--
-- Users can now correct a track's date/time from the detail panel (the pen
-- icon next to the date, added after several activities turned up defaulted
-- to midnight Jan 1 — a bad-import artifact that was polluting Relic
-- suggestions with fake mega-trips). A Strava resync used to overwrite
-- `date` unconditionally; `date_edited` makes a manual correction stick,
-- exactly like `type_edited` does for type and `name_edited` does for names.
--
-- MUST run before the matching index.html is deployed: momentToRow() now
-- sends `date_edited`, and an upsert naming a column that doesn't exist
-- fails — which would make every save fail. Idempotent; safe to re-run.

alter table public.activities
  add column if not exists date_edited boolean not null default false;

-- Same as the live function (docs/supabase-type-edit.sql) except the `date` line.
create or replace function public.strava_upsert_activities(p_rows jsonb)
returns integer
language plpgsql
as $function$
declare n integer;
begin
  insert into public.activities (
    id, user_id, name, type, date, source, strava_id, polyline,
    distance, duration, elevation, start_lat, start_lng,
    avg_hr, max_hr, calories, avg_speed, max_speed, avg_cadence,
    avg_watts, weighted_watts, suffer_score, pr_count, achievement_count,
    elev_high, elev_low, gear_id, workout_type, commute, elapsed_time,
    is_public
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
    (r->>'elapsed_time')::double precision,
    coalesce((r->>'is_public')::boolean, false)
  from jsonb_array_elements(p_rows) as r
  on conflict (user_id, id) do update set
    name           = case when public.activities.name_edited
                          then public.activities.name else excluded.name end,
    type           = case when public.activities.type_edited
                          then public.activities.type else excluded.type end,
    date           = case when public.activities.date_edited
                          then public.activities.date else excluded.date end,
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
    -- is_public deliberately excluded: never overwritten by a resync, same as
    -- note / mood / custom_color -- a user's manual privacy toggle always sticks.
  get diagnostics n = row_count;
  return n;
end $function$;
