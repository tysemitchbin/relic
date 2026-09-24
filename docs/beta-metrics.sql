-- Relic beta scorecard — read-only, safe to run any time in the Supabase SQL
-- editor. Counts from the database itself, so unlike PostHog it doesn't depend
-- on anyone accepting the analytics banner. See docs/analytics.md for how this
-- and PostHog fit together.
--
-- Signed-up accounts only (auth.users). "Activated" = at least one activity,
-- pin or relic. Change the interval on the first line to look at a cohort.

with params as (select now() - interval '365 days' as since),
u as (
  select au.id, au.created_at, au.last_sign_in_at
  from auth.users au, params where au.created_at >= params.since
),
per_user as (
  select u.id, u.created_at, u.last_sign_in_at,
    (select count(*) from public.activities a where a.user_id = u.id)                       as items,
    (select count(*) from public.activities a where a.user_id = u.id and a.strava_id is not null) as strava_items,
    (select count(*) from public.stories s where s.user_id = u.id)                          as relics,
    (select count(*) from public.story_public sp where sp.user_id = u.id)                   as relics_shared,
    (select count(*) from public.follows f where f.follower_id = u.id)                      as following,
    (select count(*) from public.follows f where f.followee_id = u.id)                     as followers
  from u
)
select
  count(*)                                                    as signed_up,
  count(*) filter (where items > 0 or relics > 0)             as activated,
  count(*) filter (where strava_items > 0)                    as imported_strava,
  count(*) filter (where relics > 0)                          as made_a_relic,
  count(*) filter (where relics_shared > 0)                   as shared_a_relic,
  count(*) filter (where following > 0)                       as follows_someone,
  count(*) filter (where followers > 0)                       as has_a_follower,
  count(*) filter (where last_sign_in_at > now() - interval '7 days')  as active_last_7d,
  count(*) filter (where last_sign_in_at > created_at + interval '7 days') as came_back_after_week_1
from per_user;

-- Per-person view (who is stuck where). Uncomment to run.
-- select p.name, u.email, u.created_at::date as joined, u.last_sign_in_at::date as last_seen,
--   (select count(*) from public.activities a where a.user_id = u.id) as items,
--   (select count(*) from public.stories s where s.user_id = u.id) as relics,
--   (select count(*) from public.story_public sp where sp.user_id = u.id) as shared,
--   (select count(*) from public.follows f where f.follower_id = u.id) as following
-- from auth.users u left join public.profiles p on p.id = u.id
-- order by u.created_at desc;
