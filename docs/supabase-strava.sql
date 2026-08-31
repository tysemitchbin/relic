-- Relic — Strava connector (Phase 6)
-- Run in the Supabase SQL Editor. Safe to run on an existing project (idempotent).

create table if not exists public.strava_connections (
  user_id       uuid primary key references auth.users on delete cascade,
  athlete_id    bigint,
  access_token  text not null,
  refresh_token text not null,
  expires_at    bigint not null,          -- unix seconds
  scope         text,
  athlete       jsonb,                    -- cached Strava athlete summary
  synced_at     timestamptz,              -- last successful activity sync
  connected_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- if the table already existed from an earlier run
alter table public.strava_connections add column if not exists synced_at timestamptz;

-- RLS on, NO policy: this table holds Strava tokens and is only ever touched by
-- the `strava` Edge Function using the service-role key. The browser learns its
-- connection state through that function's `status` action, never by reading here.
alter table public.strava_connections enable row level security;
