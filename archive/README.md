# Archive — Relic v1 (single-user)

Frozen snapshot of Relic **before** the multi-user / Supabase migration
(see `../docs/setup.md`). Kept for reference and rollback.

## What this version is

- **Single user.** No accounts, no login. All data is global.
- **Backend:** one JSON blob in Google Drive, read/written via a Google Apps
  Script web app (`APPS_SCRIPT_URL` in the file).
- **Photos:** stored as base64 data URLs *inside* that JSON blob.
- **Cache:** `localStorage` (`relic_db_v1`, `relic_profile_v1`, `relic_colors_v1`).
- **Secrets:** Strava client secret + refresh token and the Mapbox token are
  hardcoded in the HTML. These were rotated / URL-restricted during Phase 0 of
  the migration, so the copies here are inert.

## Files

| File | Notes |
|---|---|
| `index.html` | The main app. |
| `relic-bulk-import.html` | KML → Apps Script bulk importer. |

`strava-map.html` (an earlier Google-Maps prototype) is left in the repo root,
not copied here.

## Running it

Still works as long as the Apps Script deployment and its Drive file exist.
Open `index.html` directly or serve the folder statically. Once the Apps Script
is decommissioned (migration Phase 7) this version stops loading data.

Snapshot taken: 2026-08-30. Corresponds to the last commit before the
`docs/` migration planning was added.
