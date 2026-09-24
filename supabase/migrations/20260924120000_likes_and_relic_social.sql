-- Likes (not "kudos") everywhere, plus likes and comments on relics, plus a
-- shared_at on story_public so the feed can order by when a relic was shared.
-- Additive except for the kudos -> activity_likes rename, which keeps a
-- `kudos` compatibility view so the client already deployed keeps working
-- until this branch ships. Drop it afterwards:
--   drop view if exists public.kudos;

-- ── 1. kudos -> activity_likes ──────────────────────────────────────────
alter table public.kudos rename to activity_likes;
alter table public.activity_likes rename constraint kudos_pkey to activity_likes_pkey;
alter table public.activity_likes rename constraint kudos_activity_user_id_activity_id_fkey to activity_likes_activity_fkey;
alter table public.activity_likes rename constraint kudos_user_id_fkey to activity_likes_user_id_fkey;
alter index public.kudos_owner_idx rename to activity_likes_owner_idx;
alter policy "read kudos" on public.activity_likes rename to "read activity likes";
alter policy "give kudos" on public.activity_likes rename to "like an activity";
alter policy "take back kudos" on public.activity_likes rename to "remove own activity like";

-- Temporary: the live client still says `kudos`. security_invoker makes the
-- view run as the caller, so activity_likes' RLS still applies through it.
create view public.kudos with (security_invoker = true) as select * from public.activity_likes;
grant select, insert, delete on public.kudos to authenticated;

-- ── 2. Likes and comments on relics ─────────────────────────────────────
-- Same rules as on activities: only on a shared relic (a story_public row
-- exists), never by someone the owner has blocked, gone with the relic.
create table if not exists public.relic_likes (
  story_user_id uuid not null,
  story_id      text not null,
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (story_user_id, story_id, user_id),
  foreign key (story_user_id, story_id) references public.stories (user_id, id) on delete cascade
);
create index if not exists relic_likes_owner_idx on public.relic_likes (story_user_id, created_at desc);
alter table public.relic_likes enable row level security;
create policy "read relic likes" on public.relic_likes for select to authenticated using (
  user_id = auth.uid() or story_user_id = auth.uid()
  or exists (select 1 from public.story_public p where p.user_id = relic_likes.story_user_id and p.story_id = relic_likes.story_id)
);
create policy "like a relic" on public.relic_likes for insert to authenticated with check (
  user_id = auth.uid()
  and not public.is_blocked(story_user_id, user_id)
  and exists (select 1 from public.story_public p where p.user_id = relic_likes.story_user_id and p.story_id = relic_likes.story_id)
);
create policy "remove own relic like" on public.relic_likes for delete to authenticated using (user_id = auth.uid());

create table if not exists public.relic_comments (
  id            uuid primary key default gen_random_uuid(),
  story_user_id uuid not null,
  story_id      text not null,
  user_id       uuid not null default auth.uid() references auth.users on delete cascade,
  body          text not null check (char_length(body) between 1 and 1000),
  created_at    timestamptz not null default now(),
  foreign key (story_user_id, story_id) references public.stories (user_id, id) on delete cascade
);
create index if not exists relic_comments_relic_idx on public.relic_comments (story_user_id, story_id, created_at);
create index if not exists relic_comments_owner_idx on public.relic_comments (story_user_id, created_at desc);
alter table public.relic_comments enable row level security;
create policy "read relic comments" on public.relic_comments for select to authenticated using (
  user_id = auth.uid() or story_user_id = auth.uid()
  or exists (select 1 from public.story_public p where p.user_id = relic_comments.story_user_id and p.story_id = relic_comments.story_id)
);
create policy "comment on a relic" on public.relic_comments for insert to authenticated with check (
  user_id = auth.uid()
  and not public.is_blocked(story_user_id, user_id)
  and exists (select 1 from public.story_public p where p.user_id = relic_comments.story_user_id and p.story_id = relic_comments.story_id)
);
-- Your own comments, and any comment on your own relic.
create policy "delete relic comments" on public.relic_comments for delete to authenticated using (
  user_id = auth.uid() or story_user_id = auth.uid()
);

-- ── 3. Feed order: when a relic was shared ──────────────────────────────
-- Set on insert only. Snapshot re-pushes are upserts that don't send it, so
-- editing a shared relic doesn't bump it; un-sharing deletes the row, so
-- sharing again does.
alter table public.story_public add column if not exists shared_at timestamptz not null default now();
update public.story_public set shared_at = updated_at;
create index if not exists story_public_user_shared_idx on public.story_public (user_id, shared_at desc, story_id desc);
