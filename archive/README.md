# Archive — Relic v1 (single-user)

Frozen snapshot of Relic **before** the multi-user / Supabase migration
(see `../docs/setup.md`). Kept for reference and rollback.

## What this version is

- **Single user.** No accounts, no login. All data is global.
- **Backend:** one JSON blob in Google Drive, read/written via a Google Apps
  Script web app (`APPS_SCRIPT_URL` in the file).
- **Photos:** stored as base64 data URLs *inside* that JSON blob.
- **Cache:** `localStorage` (`relic_db_v1`, `relic_profile_v1`, `relic_colors_v1`).
- **Secrets:** the Mapbox token here is the current live one (kept working on
  purpose — see below). The Strava client secret + refresh token are the old
  ones; once the Strava app secret is rotated, the detail-panel charts in this
  version stop working, but everything else keeps running.

## Files

| File | Notes |
|---|---|
| `index.html` | The main app. |
| `relic-bulk-import.html` | KML → Apps Script bulk importer. |

`strava-map.html` (an earlier Google-Maps prototype) is left in the repo root,
not copied here.

## Running it

Served at `<site>/archive/index.html` on the same Cloudflare Pages deployment,
or open `index.html` directly / serve the folder statically.

**This version is kept functional**, not just frozen — the Google Apps Script
read endpoint and its Drive file stay deployed for it. Migration Phase 7 only
repoints the *bulk importer* to Supabase and stops *writing* to Drive; the Drive
read path is left alone so this archive keeps loading its data.

Snapshot taken: 2026-08-30 (last commit before the `docs/` migration planning),
with the Mapbox token refreshed 2026-08-31.
