// Shared by the Cloudflare Pages Functions (link previews). Pages Functions
// run on Cloudflare in front of the static site; nothing here ships to the
// browser. The public-relic Supabase function is the only data source.
export const PUBLIC_RELIC_FN = 'https://vacmugisahiwhvkpyxgv.supabase.co/functions/v1/public-relic';
// The same public, URL-restricted token index.html uses. Static-image
// requests from here send the site's own origin as Referer to satisfy it.
export const MAPBOX_TOKEN = 'pk.eyJ1IjoidHlzZW1pdGNoYmluIiwiYSI6ImNtdGhraWdkYTF3ankyenI2cXFyemllamkifQ.ANlteRDkZnibovVzmOw5bw';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const STORY_ID = /^[\w.-]{1,80}$/;

// { relic, author, photos, likes, comments } for a shared relic, or null.
export async function fetchPublicRelic(u, s, env) {
  if (!UUID.test(u || '') || !STORY_ID.test(s || '')) return null;
  const base = (env && env.PUBLIC_RELIC_FN) || PUBLIC_RELIC_FN;
  try {
    const r = await fetch(`${base}?u=${encodeURIComponent(u)}&s=${encodeURIComponent(s)}`, { cf: { cacheTtl: 120 } });
    if (!r.ok) return null;
    const d = await r.json();
    return d && d.relic ? d : null;
  } catch (e) { return null; }
}
