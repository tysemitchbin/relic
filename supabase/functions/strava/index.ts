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

import { createClient } from "jsr:@supabase/supabase-js@2";

const STRAVA_CLIENT_ID = Deno.env.get("STRAVA_CLIENT_ID")!;
const STRAVA_CLIENT_SECRET = Deno.env.get("STRAVA_CLIENT_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

    // Acts as the caller — RLS enforced. Also used to verify the JWT.
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: uErr } = await userClient.auth.getUser();
    if (uErr || !user) return json({ error: "invalid session" }, 401);

    // Service-role client — the only thing that reads/writes strava_connections.
    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    const body = await req.json().catch(() => ({}));
    const action = body.action as string;

    // ── exchange: first-time connect ──────────────────────────
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
        updated_at: new Date().toISOString(),
      });
      return json({ ok: true, connected: true, athlete: tok.athlete ?? null });
    }

    // ── everything else needs an existing connection ──────────
    const { data: conn } = await admin
      .from("strava_connections").select("*").eq("user_id", user.id).maybeSingle();

    if (action === "status") {
      return json({
        ok: true,
        connected: !!conn,
        athlete: conn?.athlete ?? null,
        athlete_id: conn?.athlete_id ?? null,
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
      if (!r.ok) return json({ error: `stream fetch failed (${r.status})` }, 502);
      return json({ ok: true, streams: await r.json() });
    }

    if (action === "sync") {
      // Preserve user edits: pull existing strava_* rows first
      const { data: existingRows } = await userClient
        .from("activities").select("*").like("id", "strava\\_%");
      const existing = new Map((existingRows ?? []).map((r) => [r.id, r]));

      let page = 1, seen = 0;
      const PER = 100;
      for (;;) {
        const list = await fetch(
          `https://www.strava.com/api/v3/athlete/activities?per_page=${PER}&page=${page}`,
          { headers: { Authorization: `Bearer ${accessToken}` } },
        ).then((r) => r.json());
        if (!Array.isArray(list) || list.length === 0) break;

        const rows = list.map((a) => stravaToRow(a, user.id, existing.get(`strava_${a.id}`)));
        const { error } = await userClient
          .from("activities").upsert(rows, { onConflict: "user_id,id" });
        if (error) return json({ error: `upsert failed: ${error.message}` }, 500);

        seen += list.length;
        if (list.length < PER) break;
        page++;
      }
      return json({ ok: true, synced: seen });
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

// Strava activity -> `activities` row, keeping the user's own edits intact.
function stravaToRow(a: any, userId: string, prev: any) {
  const e = prev ?? {};
  return {
    id: `strava_${a.id}`,
    user_id: userId,
    name: e.name_edited ? e.name : a.name,
    type: a.type,
    date: a.start_date_local || a.start_date || null,
    source: "strava",
    strava_id: a.id,
    polyline: a.map?.summary_polyline || e.polyline || null,
    distance: a.distance || 0,
    duration: a.moving_time || 0,
    elevation: a.total_elevation_gain || 0,
    start_lat: a.start_latlng?.[0] ?? null,
    start_lng: a.start_latlng?.[1] ?? null,
    note: e.note ?? "",
    mood: e.mood ?? null,
    custom_color: e.custom_color ?? null,
    name_edited: !!e.name_edited,
    avg_hr: a.average_heartrate ?? null,
    max_hr: a.max_heartrate ?? null,
    calories: a.calories ?? e.calories ?? null,
    avg_speed: a.average_speed ?? null,
    max_speed: a.max_speed ?? null,
    avg_cadence: a.average_cadence ?? null,
    avg_watts: a.average_watts ?? null,
    weighted_watts: a.weighted_average_watts ?? null,
    suffer_score: a.suffer_score ?? e.suffer_score ?? null,
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
