# Relic — work log

Sun Aug 30 → Wed Sep 2, 2026. One entry per commit, newest day last.
Hashes are short SHAs on `main` unless a branch is noted.

---

## Sunday, Aug 30 — Supabase migration foundation

Moved Relic off the single-user Google Drive JSON blob toward a multi-tenant
app with accounts, per-user isolation, and real photo storage.

| Commit | Summary |
|---|---|
| `ab62ac0` 19:40 | **Create `setup.md`.** The migration plan: decisions (Supabase, Cloudflare Pages, email+password auth), target architecture, and a phased rollout. |
| `4c2ddd0` 19:40 | **Create `supabase-schema.sql`.** Initial Postgres schema — `profiles`, `activities`, `stories`, `activity_photos` — with row-level security keyed on `auth.uid()`. |
| `35f174b` 19:44 | **Create `index.html`.** The v1 app committed as the migration starting point. |
| `84847d0` 19:44 | **Create `README.md`** (archive readme for the frozen v1). |
| `1ae4db8` 19:44 | **Create `relic-bulk-import.html`.** The v1 KML → Apps Script bulk importer, committed alongside v1. |
| `e3f8a45` 21:02 | **Add `migrate.html`.** One-time importer that reads the existing Drive archive and writes it into the owner's Supabase account. |
| `7e7124d` 21:56 | **Schema fix:** widen the Strava numeric columns (`distance`, `duration`, `elevation`) to `double precision` — they can be decimals. |
| `ce6c6eb` 22:07 | **Swap `index.html`'s data layer from Google Drive to Supabase.** Magic-link auth gate in front of the app; `loadFromSupabase()` does paged reads of activities/stories/photos/profile with batch-signed photo URLs, assembled into the same in-memory `db` shape. Debounced per-row upserts replace the Drive/localStorage save path. Photos resize client-side into a Storage bucket. Strava stream charts stubbed off (secret removed) pending Phase 6. Sign-out control added. |

---

## Monday, Aug 31 — Per-user Strava + beta prep

| Commit | Summary |
|---|---|
| `152c5bd` 20:18 | **Profiles read:** use a plain `limit(1)` instead of `maybeSingle()` to avoid a 401 during auth transitions. |
| `65651f4` 20:25 | Use a fresh unrestricted Mapbox token. |
| `220c761` 20:26 *(supabase-migration)* | **Keep the archived v1 working:** fresh Mapbox token for `archive/`, plus a note that the Drive read path stays live so the archive keeps loading its data. |
| `9ab67f5` 20:59 | **Per-user Strava connect (Phase 6).** One Edge Function (`supabase/functions/strava`) handles exchange/status/sync/streams/disconnect and holds the client secret, scoped to the caller's JWT. Adds `strava-callback.html` (OAuth redirect target), a `strava_connections` table (function-only via service role), and a Profile → Strava section with Connect / Sync / Disconnect. Stream charts work again once connected. |
| `d4d4af3` 21:19 | Auto-sync Strava once, right after connecting. |
| `47a4f83` 21:24 | **Incremental sync:** `after=` param, quiet auto-sync on load when data is stale >30 min, `synced_at` column, and "Sync now" / "Full re-sync" buttons. |
| `0c79457` 21:30 | **Resumable paged first import for large accounts.** Sync is client-looped (≤4 Strava pages per function call), resumes from `sync_page` if interrupted, handles 429 with backoff. A `strava_upsert_activities()` SQL function does the on-conflict merge so note/mood/colour/renamed titles survive. Adds `first_sync_done` + `sync_page` columns. |
| `d1eb924` 21:55 | Indeterminate progress bar during import, with a running activity count. |
| `f2f0b11` 22:04 | **Beta prep:** empty-state prompt on an empty archive; bulk importer gated and repointed to Supabase (Phase 7). |

---

## Tuesday, Sep 1 — Mobile pass, feedback, static maps, wishlist

The mobile work landed on the `mobile-friendly` branch (now merged).

| Commit | Summary |
|---|---|
| `fb265cf` 09:05 | Empty-state card: add a dismiss (×) button. |
| `6daaa55` 13:01 *(mobile-friendly)* | **First real mobile layout.** Bottom tab bar (Map/Feed/Archive/Profile) replaces the hamburger menu; Import/Sync/Sign out move to a mobile-only action row on Profile. Safe-area inset tokens applied throughout; `100dvh` app height for the iOS address bar; `overscroll-behavior` to kill pull-to-refresh bleed; full-screen import/story modals with sticky footers. All inside the existing 768px guards so desktop is untouched. |
| `62b1270` 14:29 *(mobile-friendly)* | **Recover from auth/JWT load failures instead of dead-ending.** A stale or clock-skewed token used to leave "Could not load your data" on screen with no way out. Now: silently `refreshSession()` and retry once; if it still fails, show Retry / "Sign out and sign in again" and include the token-vs-device clock skew for diagnosis. |
| `333b20c` 15:35 *(mobile-friendly)* | **Fix the empty-state card.** It never hid (a `display:flex` rule beat `[hidden]`) so it showed even with data and couldn't be dismissed. Also dropped `pointer-events:none`, which was eating taps on the close X and Connect/Import buttons in iOS Safari. Off-screen sheets get `pointer-events:none` so they can't intercept taps over the map. |
| `bb3af83` 16:15 *(mobile-friendly)* | **Fix scrollable popouts.** Filters/colors panel had two nested scroll containers so the last activity type was unreachable — collapsed to one scroller. Story modal body is now a single scroll container with stacked panes. Lightbox close button is a 44px target inside the safe area. |
| `c677a5d` 16:32 *(mobile-friendly)* | **Lay out header / main / tab bar in normal flow.** They were `position:fixed` and fought the iOS dynamic address bar — the header hid behind the map and a black band appeared below the tab bar. Now all three are plain flex children of `#app` (`height:100dvh`); no `position:fixed` for layout anywhere. |
| `9075747` 16:49 *(mobile-friendly HEAD)* | **Pin the filters panel between header and tab bar.** It grew upward under the fixed header and clipped its own tabs out of reach. Now `position:fixed` with both top and bottom set so its height is bounded to the safe area; content scrolls inside; opens instantly. |
| `48573dd` 17:58 | **In-app beta feedback.** New "Feedback" entry point (header on desktop, Profile action row on mobile) opens a one-box modal that writes to a new `feedback` table (RLS: testers see only their own rows; owner reads all via the Table Editor). Captures email, current view, and user agent. Needs `docs/supabase-feedback.sql` run once. |
| `12976c0` 18:22 | **Real map tiles behind the mini track** in feed cards and the profile honeycomb. A Mapbox Static Images request (outdoors style, track as a path overlay, auto-fit bbox) layered over the old canvas, which stays as the fallback. `loading="lazy"`; skipped when there's no polyline or the URL would exceed Mapbox's ~8k cap. |
| `0b24fbc` 19:12 | **Static map tiles for stories too.** `staticStoryMapImg()` puts every child moment's track on one static map, each path coloured by moment type, added until the URL budget runs out. Shared the URL builder and polyline lookup with the single-activity path. |
| `b6549a5` 21:27 | Add `docs/wishlist.md` — running feature want-list. |
| `acd962d` 21:34 | wishlist: add dopamine / delight feature ideas. |
| `88d36aa` 21:40 | wishlist: social/sharing, AI story suggestions, fly-in. |

---

## Wednesday, Sep 2 — Onboarding, auth, email deliverability

| Commit | Summary |
|---|---|
| `f5c25ba` 20:30 | **Fast onboarding.** Instant-load cache: the assembled `db`/profile is mirrored to `localStorage` per user; boot paints from it and drops the loading screen before `loadFromSupabase` returns, then refreshes behind an already-usable app. Map autoframes to the bounds of the user's own tracks on first load instead of the fixed Norway view. Returning from a Strava connect stays on the map behind a full-screen counter that ticks up as activities import, then fades the archive in — instead of dumping the user on Profile. Login prefills the last-used email; "Connect Strava" from the empty state goes straight to OAuth. Invisible 18px hit-line on tracks so you don't have to hit a 2px stroke. |
| `b1bf8d8` 21:18 *(fast-onboarding)* | **Add email + password sign-in** (magic link kept as fallback). Returning users — especially on mobile, where the magic link often opens a different browser and loses the session — can sign in instantly. Login screen gains email+password, a "Create account" toggle (`signUp`), "Forgot password" (`resetPasswordForEmail`), and a "set a new password" form when arriving on a recovery link. `friendlyAuthError()` maps common Supabase messages to plain English. |
| `d22da5e` 21:36 | **Auth email: shared 60s cooldown + clearer rate-limit messaging.** One cooldown shared across the magic-link, forgot-password, and create-account buttons, with a live countdown. `friendlyAuthError` parses Supabase's "after N seconds" / rate-limit / "signups not allowed" messages into plain text. (The real fix — custom SMTP + raised limits — is a dashboard task, documented in `setup.md`.) |
| `52bdf7a` 22:25 | **Detect password-recovery links synchronously at load.** supabase-js strips the URL hash during async session detection, so checking `location.hash` after an awaited `getSession()` could miss a recovery link and boot the app instead of showing the reset form. The recovery flag is now captured synchronously when the script first runs. |
| `a2974eb` 22:49 | **Email templates.** `docs/email-templates/` — styled reset-password, magic-link, and confirm-signup templates matching Relic's palette, plus a README with paste-in instructions and deliverability notes. |

---

## Not in git — session work, Sep 2

- **Repo review.** Confirmed `fast-onboarding`, `mobile-friendly`, and `supabase-migration` are all fully merged into `main`. Confirmed `D:\Documents\Relic\relic2` was an empty stray folder (removed). Noted there is no `.gitignore` and no root README.
- **Resend / custom SMTP.** Custom SMTP through Resend is working: `myrelicmap.com` verified, SPF / DKIM / DMARC all passing (checked against a real delivered message).
- **Spam diagnosis.** Authentication is clean; spam placement is down to (1) new-domain reputation and (2) the verify link pointing at `*.supabase.co` instead of `myrelicmap.com`. Recommended the Supabase Custom Domain add-on as the biggest remaining lever.

---

## Open items

- Delete the three merged branches (local + `origin`).
- Run `docs/supabase-feedback.sql` once so the beta feedback feature works.
- Paste the three templates from `docs/email-templates/` into Supabase; switch the SMTP sender from `noreply@` to `hello@myrelicmap.com`.
- Consider the Supabase Custom Domain add-on so auth links are on `auth.myrelicmap.com`.
- Add a `.gitignore` and a root README.
- Redesign is the next major push.
