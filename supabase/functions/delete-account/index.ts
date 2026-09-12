// Relic — Account deletion Edge Function (GDPR right to erasure)
//
// Every request must carry a valid Relic user JWT (Authorization: Bearer
// <token>); deletes only the calling user's own account, never anyone else's.
//
// Deploy from the Supabase dashboard → Edge Functions → new function
// `delete-account`. Turn OFF "Verify JWT" (we verify in code so the CORS
// preflight passes, same as the `strava` function).
//
// Two steps:
//   1. Remove every file this user owns in the `photos` storage bucket
//      (under `<user_id>/...`) — storage objects aren't covered by Postgres
//      foreign-key cascades, so they'd otherwise survive the user's own
//      deletion and leak (photos, avatar, feedback screenshots).
//   2. auth.admin.deleteUser() — every table referencing auth.users has
//      `on delete cascade` (profiles, activities, stories, activity_photos,
//      activity_private_notes, activity_public, follows both directions,
//      feedback, strava_connections), so this one call removes everything
//      else in a single transaction-safe cascade.

import { createClient } from "jsr:@supabase/supabase-js@2";

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

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: uErr } = await userClient.auth.getUser();
    if (uErr || !user) return json({ error: "invalid session" }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);

    // Storage has no real folders, just "/"-prefixed keys. list() simulates
    // folders as entries with id === null; recurse into those.
    async function collectPaths(prefix: string): Promise<string[]> {
      const { data: entries } = await admin.storage.from("photos").list(prefix, { limit: 1000 });
      if (!entries) return [];
      const paths: string[] = [];
      for (const e of entries) {
        const full = `${prefix}/${e.name}`;
        if (e.id === null) paths.push(...await collectPaths(full));
        else paths.push(full);
      }
      return paths;
    }
    const allPaths = await collectPaths(user.id);
    for (let i = 0; i < allPaths.length; i += 1000) {
      const batch = allPaths.slice(i, i + 1000);
      const { error: rmErr } = await admin.storage.from("photos").remove(batch);
      if (rmErr) return json({ error: `storage cleanup failed: ${rmErr.message}` }, 500);
    }

    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) return json({ error: `delete failed: ${delErr.message}` }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
