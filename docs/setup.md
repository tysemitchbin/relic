# Relic — Multi-user Migration & Setup

Moving Relic from a single-user Google Drive JSON blob to a multi-tenant app
with accounts, per-user data isolation, and real object storage for photos.

## Decisions

| Choice | Value | Why |
|---|---|---|
| Backend | **Supabase** | Postgres + Auth + Storage + Edge Functions, static-frontend friendly, generous free tier |
| Auth | **Magic link** (email OTP) | No passwords to manage or leak; least code |
| Hosting | **Cloudflare Pages** | Free, no bandwidth cap, auto-deploy from GitHub, free custom domain |
| Existing data | **Migrate** into the owner's account | Keep the full history |
| Audience | Me + friends/family | Skip CAPTCHA / rate-limit hardening / legal pages for now |

## Target architecture

| Concern | Before | After |
|---|---|---|
| Identity | none | Supabase Auth (magic link) |
| Data store | one JSON blob in Google Drive (Apps Script) | Postgres: `activities`, `stories`, `activity_photos`, `profiles` |
| Isolation | everything global | Row-Level Security: `user_id = auth.uid()` |
| Photos | base64 strings inside the blob | Supabase Storage bucket, resized on upload, signed URLs |
| Secrets | hardcoded in committed HTML | Strava secret → Edge Function; anon key + URL-restricted Mapbox token are safe client-side |
| Cache | `localStorage` is source of truth | `localStorage` is a per-user read cache only |

The in-memory `db` object keeps its current shape (`{ [id]: momentOrStory }`), so
the map / feed / archive / honeycomb / story / chart rendering code is left alone.
Only the code that *fills* and *persists* `db` changes.

---

## Phase 0 — Rotate leaked secrets (do first)

All three are in public git history and must be rotated (history keeps the old
strings forever — rotation is the only fix):

1. **Strava app 215759** — <https://www.strava.com/settings/api> → regenerate the
   **Client Secret**. New secret goes into a Supabase Edge Function later (Phase 6),
   not the frontend. This breaks the detail-panel charts until Phase 6 — expected.
2. **Mapbox token** — <https://account.mapbox.com/access-tokens> → add a URL
   restriction (`https://*.pages.dev/*` + the custom domain) or rotate. A
   URL-restricted token is safe to keep client-side.
3. **`strava-map.html`** — has a separate leaked secret for Strava app 148064.
   Decide: delete the prototype, or keep it and rotate that secret too.

---

## Phase 1 — Infrastructure

### 1a. Cloudflare Pages

1. <https://dash.cloudflare.com> → **Workers & Pages** → **Create** → **Pages** →
   **Connect to Git** → authorize `tysemitchbin/relic`.
2. Build settings:
   - Framework preset: **None**
   - Build command: *(empty)*
   - Build output directory: `/`
3. Deploy → note the `https://<name>.pages.dev` URL. This is `SITE_URL`.
   Every push to `main` now auto-deploys.
4. (Later) **Custom domains** tab to attach a domain; Cloudflare handles DNS + HTTPS.

### 1b. Supabase project

1. <https://supabase.com/dashboard> → **New project**. Nearest region. Free plan.
   Save the DB password.
2. **Project Settings → API** → copy **Project URL** and **anon/public key**
   (both safe to hardcode in the frontend — RLS protects the data).
3. **SQL Editor** → run `docs/supabase-schema.sql` (below, kept in sync here).

### 1c. Storage bucket

**Storage → New bucket** → name `photos`, **Private**. Then run the storage
policy from the schema file.

### 1d. Auth config

- **Authentication → Sign In / Providers → Email**: enable, turn on
  **Email OTP / Magic Link**. "Confirm email" can stay off.
- **Authentication → URL Configuration**:
  - **Site URL**: `SITE_URL`
  - **Redirect URLs**: `SITE_URL/**` and `http://localhost:5173/**` for local dev
- Rate limits: defaults are fine.

Invite-only signup is a later tweak — with RLS, a stranger who signs up just
sees an empty app.

### Schema

```sql
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

create policy "own profile"  on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
create policy "own activities" on public.activities
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own stories" on public.stories
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own photos" on public.activity_photos
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

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
-- (create the private bucket named `photos` in the dashboard first)
create policy "own photo files" on storage.objects
  for all
  using   (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
```

---

## Phase 2 — Auth gate (not started)

Login screen (email → `signInWithOtp`) in front of `index.html` and
`relic-bulk-import.html`. App boots only after a session exists. Sign-out control.
`supabase-js` v2 from CDN, `detectSessionInUrl: true` handles the magic-link return.

## Phase 3 — Swap the data layer in `index.html` (not started)

Replace `fetchDriveData` / `mergeFromDrive` / `backgroundSyncFromDrive` /
`persistToDrive` / `loadDB` / `saveDB` with Supabase queries:

- **Load**: parallel `select` of activities + stories + photos + profile → assemble `db`.
- **Save**: debounced `upsert` of the single changed row (replaces `scheduleSave`).
- Per-user `localStorage` cache for instant load, then refresh from Supabase.

## Phase 4 — Photos → Storage (not started)

`handlePhotoUpload`: resize client-side (canvas, ~1600 px, JPEG q0.8) → upload to
`photos/<uid>/<activityId>/<uuid>.jpg` → insert `activity_photos` row. Signed URLs
for display. Profile photo the same → `profiles.avatar_path` (currently not synced
at all — localStorage only).

## Phase 5 — One-time data migration (not started)

**No Node locally** → do it as an in-browser tool (same pattern as
`relic-bulk-import.html`): sign in as the owner, the page fetches the current
Drive JSON (`?action=data`), writes every activity/story via `supabase-js`,
decodes + uploads every embedded base64 photo. Run once, then delete the tool.

## Phase 6 — Strava "Connect" (per-user)

Any signed-in user links their own Strava from **Profile → Strava → Connect**.
One Relic Strava API app (client id `215759`), each user OAuths through it.

**Code (already in the repo):**
- `supabase/functions/strava/index.ts` — one Edge Function, routed by `action`:
  `exchange` (first connect), `status`, `sync`, `streams`, `disconnect`. Holds
  the client secret. `sync` is **resumable & paged** (≤4 Strava pages per call,
  client loops with progress), so a first import of a multi-thousand-activity
  account can't time out and resumes from `sync_page` if interrupted. Strava 429
  → returns `rateLimited` and the client backs off ~15 min.
- `strava-callback.html` — OAuth redirect target; exchanges the code, returns to `/`.
- `docs/supabase-strava.sql` — `strava_connections` table (RLS on, no policy)
  **plus** `strava_upsert_activities()`, a merge helper so syncs never clobber a
  user's note / mood / colour / renamed title.
- `index.html` — Profile "Strava" section; load-time incremental auto-sync (only
  once the first import is complete); `fetchStravaStreams` routed to the function.

**Deploy steps:**
1. **SQL Editor** → run `docs/supabase-strava.sql`.
2. **Strava** → <https://www.strava.com/settings/api> → set **Authorization
   Callback Domain** to `relic-bju.pages.dev`. Note the **Client ID** and
   **Client Secret** (rotate the secret here if it was ever exposed).
3. **Supabase → Edge Functions → Deploy a new function** → name `strava` →
   paste `supabase/functions/strava/index.ts` → **turn OFF "Verify JWT"**
   (the function verifies the caller itself; this lets the CORS preflight through).
4. **Edge Functions → `strava` → Secrets** → add:
   - `STRAVA_CLIENT_ID` = your client id (e.g. `215759`)
   - `STRAVA_CLIENT_SECRET` = your client secret
   (`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)
5. Deploy `main`, open Relic → Profile → **Connect Strava**.

If `215759` isn't your app any more, change `STRAVA_CLIENT_ID` in `index.html`
too (it's public — only the secret is sensitive).

## Phase 7 — Retire the Apps Script write path (done)

`relic-bulk-import.html` now has a magic-link gate and writes straight to
Supabase (`upsert` on `activities`; purge = `delete().eq('source','kml_import')`,
RLS-scoped to the signed-in user). The Apps Script URL field is gone.

**Leave the Drive *read* endpoint deployed** — `archive/index.html` still uses it
(see `archive/README.md`). Nothing writes to Drive any more.
