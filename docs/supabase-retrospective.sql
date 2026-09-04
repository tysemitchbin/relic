-- Relic — Retrospective entry (Pins, manual entry, NL route parser, draw-route, Airports, cover photo)
-- Run in the Supabase SQL Editor. Idempotent — safe to re-run.

-- Pins: point Moments (isPin=true) with no polyline, just a category + coords.
alter table public.activities add column if not exists is_pin boolean not null default false;
alter table public.activities add column if not exists pin_category text;

-- Named/labeled endpoints — needed so a Flight Moment (from the NL parser) can
-- carry an airport label at each end, and so manual-entry Moments can record
-- separate start/end locations without a polyline.
alter table public.activities add column if not exists end_lat double precision;
alter table public.activities add column if not exists end_lng double precision;
alter table public.activities add column if not exists start_place text;
alter table public.activities add column if not exists end_place text;

-- Cover photo: one flag per photo row, not a duplicated image or a separate
-- reference on the activity (survives a photo being deleted/reordered cleanly).
alter table public.activity_photos add column if not exists is_cover boolean not null default false;
