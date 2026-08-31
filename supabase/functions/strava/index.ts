// Relic — Strava connector Edge Function
//
// One function, routed by `action` in the POST body. Holds the Strava client
// secret (set as a Supabase secret, never in the repo). Every request must carry
// a valid Relic user JWT (Authorization: Bearer <token>); all work is scoped to
// that user.
//
// Deploy from the Supabase dashboard → Edge Functions → new function `strava`.
// Turn OFF "Verify JWT" (we verify in code so the CORS preflight passes).
// Secrets to set:  STRAVA_CLIENT_ID,  STRAVA_CLIENT_SECRET
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected.)
//
// Sync design — resumable & rate-limit aware:
//   The client calls action:"sync" in a loop. Each call fetches up to
//   PAGES_PER_CALL pages (100 activities each) from Strava, hands them to the
//   `strava_upsert_activities` SQL function (which merges without clobbering the
//   user's note/mood/colour/renamed-title), and returns { done, nextPage }.
//   - First sync of a big account = many short calls, progress shown, resumes
//     from `sync_page` if the tab is closed mid-way.
//   - Later syncs pass no page and use `after=<newest>` → usually one call.
//   - Strava 429 → returns { rateLimited, retryAfterSec }; the client backs off.

import { createClient } from "jsr:@supabase/supabase-js@2";

const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID")!;
const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const PER = 100;            // Strava max per_page
const PAGES_PER_CALL = 4;   // ~400 activities per invocation — well under the timeout

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "missing auth" }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: uErr } = await userClient.auth.getUser();
    if (uErr || !user) return json({ error: "invalid session" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const body = await req.json().catch(() => ({}));
    const action = body.action as string;

    // ── exchange: first-time connect ─────────────────────────
    if (action === "exchange") {
      if (!body.code) return json({ error: "missing code" }, 400);
      const tok = await fetch("https://www.strava.com/oauth/token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          client_id: STRAVA_CLIENT_ID,
          client_secret: STRAVA_CLIENT_SECRET,
          code: body.code,
          grant_type: "authorization_code",
        }),
      }).then((r) => r.json());

      if (!tok.access_token) return json({ error: "strava rejected the code", detail: tok }, 400);

      await admin.from("strava_connections").upsert({
        user_id: user.id,
        athlete_id: tok.athlete?.id ?? null,
        access_token: tok.access_token,
        refresh_token: tok.refresh_token,
        expires_at: tok.expires_at,
        scope: body.scope ?? null,
        athlete: tok.athlete ?? null,
        first_sync_done: false,
        sync_page: 1,
        updated_at: new Date().toISOString(),
      });
      return json({ ok: true, connected: true, athlete: tok.athlete ?? null });
    }

    // ── everything else needs an existing connection ─────────
    const { data: conn } = await admin
      .from("strava_connections").select("*").eq("user_id", user.id).maybeSingle();

    if (action === "status") {
      return json({
        ok: true,
        connected: !!conn,
        athlete: conn?.athlete ?? null,
        athlete_id: conn?.athlete_id ?? null,
        synced_at: conn?.synced_at ?? null,
        first_sync_done: !!conn?.first_sync_done,
      });
    }

    if (!conn) return json({ error: "not connected" }, 400);
    const accessToken = await ensureFreshToken(admin, conn);

    if (action === "disconnect") {
      await fetch("https://www.strava.com/oauth/deauthorize", {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}` },
      }).catch(() => {});
      await admin.from("strava_connections").delete().eq("user_id", user.id);
      return json({ ok: true, connected: false });
    }

    if (action === "streams") {
      if (!body.activityId) return json({ error: "missing activityId" }, 400);
      const r = await fetch(
        `https://www.strava.com/api/v3/activities/${body.activityId}` +
          `/streams?keys=heartrate,velocity_smooth,altitude,cadence,watts,time&key_by_type=true`,
        { headers: { Authorization: `Bearer ${accessToken}` } },
      );
      if (r.status === 429) return json({ ok: true, rateLimited: true, retryAfterSec: 900 });
      if (!r.ok) return json({ error: `stream fetch failed (${r.status})` }, 502);
      return json({ ok: true, streams: await r.json() });
    }

    if (action === "sync") {
      const forceFull = !!body.full;
      const firstSync = !conn.first_sync_done && !forceFull;
      const incremental = !firstSync && !forceFull;

      // Where to start paging
      let page = 1;
      if (body.page) page = Math.max(1, parseInt(String(body.page)) || 1);
      else if (firstSync) page = conn.sync_page || 1;

      // Incremental window — only new activities since our newest one
      let afterParam = "";
      if (incremental) {
        const { data: latest } = await userClient
          .from("activities").select("date").eq("source", "strava")
          .order("date", { ascending: false }).limit(1);
        const newest = latest?.[0]?.date;
        if (newest) {
          afterParam = `&after=${Math.floor(new Date(newest).getTime() / 1000) - 86400}`;
        }
      }

      let seen = 0, done = false, rateLimited = false;

      for (let i = 0; i < PAGES_PER_CALL; i++) {
        const resp = await fetch(
          `https://www.strava.com/api/v3/athlete/activities?per_page=${PER}&page=${page}${afterParam}`,
          { headers: { Authorization: `Bearer ${accessToken}` } },
        );

        if (resp.status === 429) { rateLimited = true; break; }
        if (!resp.ok) {
          return json({ error: `strava list failed (${resp.status})`, nextPage: page }, 502);
        }

        const list = await resp.json();
        if (!Array.isArray(list) || list.length === 0) { done = true; break; }

        const rows = list.map((a: any) => stravaRow(a, user.id));
        const { error } = await userClient.rpc("strava_upsert_activities", { p_rows: rows });
        if (error) return json({ error: `upsert failed: ${error.message}`, nextPage: page }, 500);

        seen += list.length;
        if (list.length < PER) { done = true; break; }
        page++;
      }

      // Persist progress
      const patch: Record<string, unknown> = {};
      if (firstSync) patch.sync_page = done ? 1 : page;
      if (done) {
        patch.synced_at = new Date().toISOString();
        if (firstSync) patch.first_sync_done = true;
      }
      if (Object.keys(patch).length) {
        await admin.from("strava_connections").update(patch).eq("user_id", user.id);
      }

      return json({
        ok: true,
        synced: seen,
        done,
        nextPage: done ? null : page,
        rateLimited,
        retryAfterSec: rateLimited ? 900 : 0,
        phase: forceFull ? "full" : firstSync ? "first" : "incremental",
      });
    }

    return json({ error: `unknown action: ${action}` }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});

async function ensureFreshToken(admin: ReturnType<typeof createClient>, conn: any) {
  const now = Math.floor(Date.now() / 1000);
  if (conn.expires_at && conn.expires_at - 120 > now) return conn.access_token as string;

  const tok = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: STRAVA_CLIENT_ID,
      client_secret: STRAVA_CLIENT_SECRET,
      grant_type: "refresh_token",
      refresh_token: conn.refresh_token,
    }),
  }).then((r) => r.json());

  if (!tok.access_token) throw new Error("strava token refresh failed");
  await admin.from("strava_connections").update({
    access_token: tok.access_token,
    refresh_token: tok.refresh_token,
    expires_at: tok.expires_at,
    updated_at: new Date().toISOString(),
  }).eq("user_id", conn.user_id);
  return tok.access_token as string;
}

// Strava summary activity -> row for strava_upsert_activities().
// Fields the summary endpoint doesn't include (calories, suffer_score,
// elev_high/low) come back null; the SQL function coalesces those so a prior
// detailed value survives.
function stravaRow(a: any, userId: string) {
  return {
    id: `strava_${a.id}`,
    user_id: userId,
    name: a.name ?? "Untitled",
    type: a.type ?? "Other",
    date: a.start_date_local || a.start_date || null,
    strava_id: a.id,
    polyline: a.map?.summary_polyline || null,
    distance: a.distance || 0,
    duration: a.moving_time || 0,
    elevation: a.total_elevation_gain || 0,
    start_lat: a.start_latlng?.[0] ?? null,
    start_lng: a.start_latlng?.[1] ?? null,
    avg_hr: a.average_heartrate ?? null,
    max_hr: a.max_heartrate ?? null,
    calories: a.calories ?? null,
    avg_speed: a.average_speed ?? null,
    max_speed: a.max_speed ?? null,
    avg_cadence: a.average_cadence ?? null,
    avg_watts: a.average_watts ?? null,
    weighted_watts: a.weighted_average_watts ?? null,
    suffer_score: a.suffer_score ?? null,
    pr_count: a.pr_count ?? null,
    achievement_count: a.achievement_count ?? null,
    elev_high: a.elev_high ?? null,
    elev_low: a.elev_low ?? null,
    gear_id: a.gear_id ?? null,
    workout_type: a.workout_type ?? null,
    commute: a.commute ?? false,
    elapsed_time: a.elapsed_time ?? null,
  };
}
