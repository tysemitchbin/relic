// public-relic — one shared relic, readable without an account.
//
// GET ?u=<owner uuid>&s=<story id>  →  { relic, author, photos, likes, comments }
//
// Deliberately a function rather than an anon RLS policy on story_public: it
// only ever answers for an exact (owner, relic) pair, so a signed-out caller
// can open a relic they were sent a link to but can't list or browse any
// others. It reads with the service role, so it must only ever return what
// story_public already holds (the owner's redacted snapshot), plus signed
// URLs for that snapshot's own photos. Used by the signed-out relic page in
// index.html and by the link-preview function (functions/index.js).
import { createClient } from "npm:@supabase/supabase-js@2";

const HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Content-Type": "application/json",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STORY_ID = /^[\w.-]{1,80}$/;
const PHOTO_TTL = 60 * 60 * 6; // 6 h — long enough for a visit, short enough not to leak for good
const json = (body: unknown, status = 200, cache = "no-store") =>
  new Response(JSON.stringify(body), { status, headers: { ...HEADERS, "Cache-Control": cache } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: HEADERS });
  const url = new URL(req.url);
  const u = url.searchParams.get("u") || "", s = url.searchParams.get("s") || "";
  if (!UUID.test(u) || !STORY_ID.test(s)) return json({ error: "not found" }, 404);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: row, error } = await sb.from("story_public")
    .select("user_id,story_id,title,narrative,mood,date_start,date_end,moment_count,distance,duration,elevation,type_counts,polylines,colors,glyph_style,glyph_colour,glyph_ink,glyph_tracks,photos,shared_at")
    .eq("user_id", u).eq("story_id", s).maybeSingle();
  if (error) return json({ error: "unavailable" }, 500);
  if (!row) return json({ error: "not found" }, 404);

  const [{ data: prof }, likes, comments] = await Promise.all([
    sb.from("profiles").select("name,avatar_path").eq("id", u).maybeSingle(),
    sb.from("relic_likes").select("user_id", { count: "exact", head: true }).eq("story_user_id", u).eq("story_id", s),
    sb.from("relic_comments").select("id", { count: "exact", head: true }).eq("story_user_id", u).eq("story_id", s),
  ]);

  // Only paths the snapshot itself lists — never anything else in the bucket.
  const paths = (row.photos || []).filter((p: unknown) => typeof p === "string").slice(0, 12);
  const signed = paths.length ? (await sb.storage.from("photos").createSignedUrls(paths, PHOTO_TTL)).data || [] : [];
  let avatarUrl = null;
  if (prof?.avatar_path) {
    avatarUrl = (await sb.storage.from("photos").createSignedUrl(prof.avatar_path, PHOTO_TTL)).data?.signedUrl || null;
  }

  const { photos: _paths, ...relic } = row;
  return json({
    relic,
    author: { name: prof?.name || "Someone", avatarUrl },
    photos: signed.map((x: { signedUrl?: string }) => x.signedUrl).filter(Boolean),
    likes: likes.count || 0,
    comments: comments.count || 0,
  }, 200, "public, max-age=120");
});
