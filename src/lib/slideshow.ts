/**
 * 写真幻灯片纯逻辑（play 页播放器调用）：部分 m3u8 的视频轨是 PNG/JPEG 图＋独立音频轨，
 * hls.js 播不了图，改播音频＋按轴换图。本文件无 DOM/fetch 依赖，可单测。
 */

export interface SlideItem {
  start: number;
  dur: number;
  url: string;
}

const IMAGE_SEG_RE = /\.(image|jpe?g|png)(\?|$)/i;
const MEDIA_SEG_RE = /\.(ts|mp4|m4s|cmfv|cmfa|m3u8)(\?|$)/i;

function absUrl(u: string, base: string): string {
  const t = (u || '').trim();
  if (!t) return '';
  if (/^https?:\/\//i.test(t)) return t;
  try {
    return new URL(t, base).href;
  } catch {
    return t;
  }
}

/** master 里找音频轨＋首个视频 variant */
export function parseMasterForSlideshow(
  masterText: string,
  baseUrl: string
): { audioUrl: string; variantUrl: string } | null {
  const lines = String(masterText || '').split('\n');
  let audioUri = '';
  let variantUrl = '';
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i].trim();
    if (ln.startsWith('#EXT-X-MEDIA:')) {
      const m = ln.match(/URI="([^"]+)"/);
      if (m && m[1]) audioUri = absUrl(m[1], baseUrl);
    } else if (ln.startsWith('#EXT-X-STREAM-INF:')) {
      const next = (lines[i + 1] || '').trim();
      if (next && !next.startsWith('#')) {
        variantUrl = absUrl(next, baseUrl);
        break;
      }
    }
  }
  if (!variantUrl || !audioUri) return null;
  return { audioUrl: audioUri, variantUrl };
}

/** variant 里按 EXTINF 攒幻灯片轴（start 累加） */
export function parseVariantSlides(
  variantText: string,
  baseUrl: string
): { slides: SlideItem[]; total: number } {
  const lines = String(variantText || '').split('\n');
  const slides: SlideItem[] = [];
  let t = 0;
  for (let i = 0; i < lines.length; i++) {
    const d = lines[i].trim().match(/^#EXTINF:([\d.]+)/);
    if (!d) continue;
    const dur = parseFloat(d[1]) || 0;
    const u = absUrl(lines[i + 1] || '', baseUrl);
    if (!u || u.startsWith('#')) continue;
    slides.push({ start: t, dur, url: u });
    t += dur;
  }
  return { slides, total: t };
}

/** 分片地址看着像图吗 */
export function isImageSegUrl(url: string): boolean {
  return IMAGE_SEG_RE.test(url || '');
}

/** 分片地址看着像正常视频吗（ts/mp4/子列表） */
export function isMediaSegUrl(url: string): boolean {
  return MEDIA_SEG_RE.test(url || '');
}

/** JPEG/PNG 魔数判定（嗅探用，extensionless 的 gdrive 链接用得上） */
export function isImageMagic(b: Uint8Array): boolean {
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return true;
  if (
    b.length >= 8 &&
    b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47
  )
    return true;
  return false;
}

/** 按播放时间找当前图（二分） */
export function findSlideIndex(
  slides: SlideItem[],
  t: number
): number {
  let lo = 0;
  let hi = slides.length - 1;
  let idx = 0;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (slides[mid].start <= t) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return idx;
}
