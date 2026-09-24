// /og/relic?u=<owner>&s=<relic> — the preview image for a shared relic link:
// its (already privacy-redacted) tracks on a Mapbox static map, 1200×630.
// Falls back to the generic og-image.jpg for anything that isn't a shared
// relic or when the map can't be drawn.
import { fetchPublicRelic, MAPBOX_TOKEN } from '../_shared.js';

export async function onRequestGet(ctx) {
  const url = new URL(ctx.request.url);
  const fallback = () => Response.redirect(`${url.origin}/og-image.jpg`, 302);
  const data = await fetchPublicRelic(url.searchParams.get('u'), url.searchParams.get('s'), ctx.env);
  if (!data) return fallback();

  const r = data.relic, overlays = [];
  let budget = 7400;
  (r.polylines || []).forEach((p, i) => {
    const hex = String((r.colors || [])[i] || '#C1502E').replace('#', '').replace(/[^0-9a-f]/gi, '').slice(0, 6) || 'C1502E';
    const seg = `path-5+${hex}-0.95(${encodeURIComponent(p)})`;
    if (seg.length + 1 <= budget) { overlays.push(seg); budget -= seg.length + 1; }
  });
  if (!overlays.length) return fallback();

  const img = `https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/${overlays.join(',')}/auto/1200x630`
    + `?access_token=${MAPBOX_TOKEN}&padding=70&logo=false&attribution=false`;
  const m = await fetch(img, { headers: { Referer: `${url.origin}/` }, cf: { cacheTtl: 86400, cacheEverything: true } });
  if (!m.ok) return fallback();
  return new Response(m.body, {
    headers: { 'Content-Type': m.headers.get('content-type') || 'image/png', 'Cache-Control': 'public, max-age=86400' },
  });
}
