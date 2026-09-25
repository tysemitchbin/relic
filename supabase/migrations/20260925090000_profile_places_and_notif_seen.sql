-- Two additive profile columns (2026-09-25):
--  notif_seen_at  — "notifications seen up to", shared across devices. Was
--                   per-device localStorage only, so reading them on a phone
--                   left the desktop saying "8 new" for ever.
--  places_summary — {countries, cities} counts the owner's device computes
--                   (Places), so other people can see them on the profile.
--                   Counts only: never which places.
alter table public.profiles add column if not exists notif_seen_at timestamptz;
alter table public.profiles add column if not exists places_summary jsonb;
