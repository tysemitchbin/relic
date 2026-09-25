# Relic analytics

Two sources, used together:

| Source | What it's good for | Blind spot |
|---|---|---|
| **PostHog** (events below) | *How* people move through the app: which paths lead to a first relic, what gets shared, where people stall | Only users who accepted the analytics banner (EU opt-in) |
| **`docs/beta-metrics.sql`** (Supabase) | The honest head-count: how many signed up, activated, made/shared a relic, came back | No "how" — only end states |

During the beta, read the SQL scorecard weekly for the numbers and PostHog
for the reasons.

## Consent

PostHog starts opted-out. Events fired before the banner is answered are
held in `localStorage` (`relic_analytics_queue_v1`, max 100) and sent with
their original timestamps only if the user accepts; declining (or signing
out) discards them. Nothing leaves the device without consent. All events go
through `track(event, props)` in `index.html` — never call `posthog.capture`
directly. `track()` is a no-op in `?demo` and on `localhost`.

## Events

| Event | Fires when | Properties | Question it answers |
|---|---|---|---|
| `app_opened` | Once per load, after the archive has rendered | `activities`, `pins`, `relics`, `relics_shared`, `has_strava` (also set as person properties) | Retention: do people come back? How set-up are they? |
| `onboarding_completed` | New account saves its name | `via_link` (`relic`/`activity`/`profile`/null), `photo`, `bio` | How many sign-ups came from a shared link? |
| `view_opened` | Any tab/page switch | `view` | What do people actually use? |
| `strava_connected` | Back from the Strava connect screen | — | Import funnel step |
| `strava_import_completed` | A Strava sync finishes | `activities`, `full` | Did the import work, and how big? |
| `file_import_completed` | GPX/KML import saved | `activities` | Import funnel (non-Strava) |
| `pin_added` | Pin saved | `category` | Are non-athletes filling their map? |
| `activity_added` | Manual entry / described trip / drawn route saved | `method` (`manual`/`describe`/`draw`), `type`, `legs` | Which no-GPS ways of adding things get used |
| `relic_created` | A new relic is saved | `source` (`suggestion`/`manual`/`describe`), `one_tap` (saved straight from a suggestion card), `activities` | **Core action.** Do suggestions drive relics? |
| `relic_suggestion_dismissed` | A suggestion is dismissed | — | Are suggestions any good? |
| `relic_shared` / `relic_unshared` | Relic made public / private | `activities` | **Core action.** |
| `link_shared` | A share link went out (share sheet or clipboard) | `kind` (`own_profile`/`profile`/`activity`/`relic`), `method` | Growth loop, outbound |
| `image_shared` | Share-as-image or glyph PNG | `kind` (`activity`/`relic`/`glyph`) | Which artwork people share |
| `link_opened` | A signed-in person opens a shared link | `kind`, `own` | Growth loop, inbound |
| `public_relic_viewed` | A signed-out visitor sees the public relic page | `photos`, `likes` | Growth loop: do shared links get opened? (Queued until they sign up and accept analytics) |
| `public_relic_cta` | That visitor taps sign up / sign in | `action` (`signup`/`signin`) | Does the page convert? Pair with `onboarding_completed` `via_link: relic` |
| `followed` | Follow succeeds | `source` (the view it happened in) | Where the graph grows |
| `like_given` / `comment_posted` | Like / comment saved | `kind` (`activity`/`relic`) | The reward loop |

Adding an event: call `track()` at the point the thing has *succeeded*
(after the save, not on the button click), add a row here, keep property
names snake_case and values small (no names, notes or other user text).

## Setting up PostHog (one-time, ~15 minutes)

Log in at <https://eu.posthog.com>. Events appear under **Activity** a few
seconds after they fire, so do one of each on the real site first (and
accept the analytics banner on that device).

1. **The core funnel.** First make one "added something" step: *Data
   management → Actions → New action*, name it **"Added to map"**, and add
   three match groups (they're OR'ed): event `strava_import_completed`,
   event `file_import_completed`, event `pin_added`. Then *Product
   analytics → New insight → Funnels*, steps: `onboarding_completed` →
   action "Added to map" → `relic_created` → `relic_shared` →
   `link_shared`. Conversion window: 14 days. Save as **"Activation
   funnel"**.
2. **Retention.** *New insight → Retention.* Start event
   `onboarding_completed`, return event `app_opened`, weekly. Save as
   **"Weekly retention"**. This is the number that decides whether Relic
   works: during the beta, aim for ~30%+ of people still opening it in
   week 4.
3. **Where relics come from.** *New insight → Trends*, event
   `relic_created`, breakdown by `source`. Save as **"Relics by source"**.
4. **Growth loop.** *Trends*, events `link_shared` and `link_opened`, and
   `onboarding_completed` filtered to `via_link` is set. Save as
   **"Sharing"**.
5. **What gets used.** *Trends*, event `view_opened`, breakdown by `view`.
6. *Dashboards → New dashboard* **"Beta"**, and add all five insights to it.

Person profiles are keyed on the Supabase user id (with email as a
property), so any person in PostHog can be matched to their row in
Supabase.
