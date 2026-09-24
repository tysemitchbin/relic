// Link previews for the app page. WhatsApp, iMessage, Slack etc. don't run
// JavaScript, so a shared relic link (/?u=<owner>&s=<relic>) would otherwise
// preview as the generic Relic card. For those links this rewrites the
// <title> and Open Graph tags from the public-relic function; every other
// request only gets its og:image made absolute (crawlers need that).
import { fetchPublicRelic } from './_shared.js';

const esc = (v) => String(v).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function describe(r) {
  if (r.narrative) return r.narrative.replace(/\s+/g, ' ').trim().slice(0, 180);
  const bits = [];
  if (r.moment_count) bits.push(`${r.moment_count} ${r.moment_count === 1 ? 'activity' : 'activities'}`);
  if (r.distance > 0) bits.push(`${Math.round(r.distance / 100) / 10} km`);
  return bits.length ? bits.join(' · ') + ' — a relic on Relic' : 'A relic on Relic';
}

export async function onRequestGet(ctx) {
  const url = new URL(ctx.request.url);
  const res = await ctx.next();
  const type = res.headers.get('content-type') || '';
  if (!type.includes('text/html')) return res;

  const u = url.searchParams.get('u'), s = url.searchParams.get('s');
  const data = u && s ? await fetchPublicRelic(u, s, ctx.env) : null;
  const set = (attr) => ({ element(e) { e.setAttribute('content', attr); } });

  let rw = new HTMLRewriter()
    .on('meta[property="og:image"]', { element(e) { const c = e.getAttribute('content') || ''; if (!/^https?:/.test(c)) e.setAttribute('content', new URL(c, url.origin).href); } });
  if (data) {
    const r = data.relic, who = data.author?.name || 'Someone';
    const title = `${r.title || 'A relic'} — ${who} on Relic`;
    const desc = describe(r);
    const img = `${url.origin}/og/relic?u=${encodeURIComponent(u)}&s=${encodeURIComponent(s)}`;
    rw = rw
      .on('title', { element(e) { e.setInnerContent(title); } })
      .on('meta[name="description"]', set(desc))
      .on('meta[property="og:title"]', set(title))
      .on('meta[property="og:description"]', set(desc))
      .on('meta[property="og:image"]', set(img))
      .on('meta[property="og:type"]', set('article'))
      .on('head', { element(e) { e.append(`<meta property="og:url" content="${esc(url.href)}">`, { html: true }); } });
  }
  return rw.transform(res);
}
