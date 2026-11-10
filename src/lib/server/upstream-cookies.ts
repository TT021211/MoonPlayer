/* eslint-disable no-console */

/**
 * 上游 Cookie 罐：某些站的 CDN 边缘验 Cookie，无 Cookie 直接 410/403
 * （如 pornhub：hv-h.phncdn.com 无会话 Cookie 回 410 Gone）。
 * 抓一次源站落地页拿 Set-Cookie，内存缓存复用；拿不到就回退无 Cookie（原行为）。
 * Cookie 只发给本站自家域名（host 后缀白名单），不往第三方漏。
 */

const jar = new Map<string, { cookie: string; exp: number }>();
const COOKIE_TTL_MS = 12 * 3600 * 1000;
const BOOTSTRAP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

interface CookieRule {
  bootstrap: string;
  hosts: string[];
}

const RULES: Record<string, CookieRule> = {
  // 注意：pornhub 曾在此处配过规则，后证实是错的——它的边缘验的是“签名新鲜度”，
  // 无 Cookie + 2h 内新签名直接 200；反而把别处抓来的 Cookie（不同会话）带上必 410。
  // 教训：加规则前必须用“新鲜签名 × 有/无 Cookie”对照验，别拿过期签名测。
};

function parseSetCookies(res: Response): string {
  let raw: string[] = [];
  try {
    const fn = (res.headers as unknown as { getSetCookie?: () => string[] }).getSetCookie;
    if (typeof fn === 'function') raw = fn.call(res.headers);
  } catch {
    /* ignore */
  }
  const map = new Map<string, string>();
  for (const line of raw) {
    const m = line.match(/^\s*([^=;\s]+)=([^;]*)/);
    if (!m) continue;
    if (/^(expires|path|domain|max-age|samesite)$/i.test(m[1])) continue;
    map.set(m[1], m[2]);
  }
  const parts: string[] = [];
  map.forEach((v, k) => parts.push(`${k}=${v}`));
  return parts.join('; ');
}

function ruleFor(source: string | null, url: string): CookieRule | null {
  let host = '';
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
  // 优先按 URL 域名认站（自建源走代理时 source=directplay，认不出真实站）
  for (const key of Object.keys(RULES)) {
    const rule = RULES[key];
    if (rule.hosts.some((h) => host === h || host.endsWith('.' + h))) return rule;
  }
  if (source && RULES[source]) return RULES[source];
  return null;
}

export async function getUpstreamCookie(source: string | null, url: string): Promise<string> {
  const rule = ruleFor(source, url);
  if (!rule) return '';
  const key = Object.keys(RULES).find((k) => RULES[k] === rule) || 'default';
  const now = Date.now();
  const hit = jar.get(key);
  if (hit && now < hit.exp) return hit.cookie;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 15000);
    let res: Response;
    try {
      res = await fetch(rule.bootstrap, {
        headers: { 'User-Agent': BOOTSTRAP_UA },
        signal: ctrl.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) return hit?.cookie || '';
    try {
      await res.arrayBuffer();
    } catch {
      /* ignore */
    }
    const cookie = parseSetCookies(res);
    if (cookie) jar.set(key, { cookie, exp: now + COOKIE_TTL_MS });
    return cookie || hit?.cookie || '';
  } catch {
    return hit?.cookie || '';
  }
}

export async function withUpstreamCookies(
  source: string | null,
  url: string,
  headers: Record<string, string>
): Promise<Record<string, string>> {
  if (headers.Cookie) return headers;
  const cookie = await getUpstreamCookie(source, url);
  if (cookie) headers.Cookie = cookie;
  return headers;
}
