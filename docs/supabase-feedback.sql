-- Relic — Beta feedback
-- Run in the Supabase SQL Editor. Idempotent — safe to re-run.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,
  email       text,                       -- denormalized copy of the sender's email, for the dashboard
  message     text not null,
  context     text,                       -- view they were on when they sent it: map | feed | stats | profile
  user_agent  text,
  created_at  timestamptz not null default now()
);
create index if not exists feedback_user_created_idx
  on public.feedback (user_id, created_at desc);

-- RLS on: a tester can insert/see/withdraw their own feedback, nobody else's.
-- You read everything as the project owner via the Supabase dashboard Table
-- Editor, which uses the service role and bypasses RLS.
alter table public.feedback enable row level security;
create policy "own feedback" on public.feedback
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
