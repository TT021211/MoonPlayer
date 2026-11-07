/* eslint-disable no-console */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

/**
 * 代理磁盘缓存（VPS 落盘、边看边存）：
 * - 播放列表（m3u8 文本）：短 TTL（token 化地址换得勤，默认 1h）
 * - 分片/密钥（二进制）：长 TTL（内容不可变，默认 72h）
 * - 总量上限 LRU（默认 10GB）＋ TTL 双清扫；看完由播放页 keepalive DELETE 精确清除
 */

const DIR =
  process.env.PROXY_CACHE_DIR || path.join(process.cwd(), '.data', 'proxy-cache');
const SEG_TTL_MS =
  Number(process.env.PROXY_CACHE_SEG_TTL_H || 72) * 3600 * 1000;
const LIST_TTL_MS =
  Number(process.env.PROXY_CACHE_LIST_TTL_H || 1) * 3600 * 1000;
const MAX_BYTES =
  Number(process.env.PROXY_CACHE_MAX_GB || 10) * 1024 * 1024 * 1024;

function ensureDir(): void {
  try {
    fs.mkdirSync(DIR, { recursive: true });
  } catch {
    /* ignore */
  }
}

export function proxyCacheKey(s: string): string {
  return crypto.createHash('sha256').update(s).digest('hex');
}

const segFile = (url: string) =>
  path.join(DIR, `s-${proxyCacheKey(url)}.bin`);
const segMetaFile = (url: string) =>
  path.join(DIR, `s-${proxyCacheKey(url)}.meta.json`);
const listFile = (key: string) =>
  path.join(DIR, `l-${proxyCacheKey(key)}.m3u8`);
const idxFile = (key: string) =>
  path.join(DIR, `l-${proxyCacheKey(key)}.idx.json`);

function fresh(p: string, ttlMs: number): boolean {
  try {
    const st = fs.statSync(p);
    return Date.now() - st.mtimeMs < ttlMs;
  } catch {
    return false;
  }
}

function touch(p: string): void {
  try {
    const t = new Date();
    fs.utimesSync(p, t, t);
  } catch {
    /* ignore */
  }
}

/** 读分片缓存（命中返回 {data, contentType}，并刷新 atime 供 LRU/TTL 用） */
export function readCachedSeg(url: string): {
  data: Buffer;
  contentType: string;
} | null {
  ensureDir();
  const f = segFile(url);
  if (!fresh(f, SEG_TTL_MS)) return null;
  try {
    const data = fs.readFileSync(f);
    let contentType = 'video/mp2t';
    try {
      const meta = JSON.parse(fs.readFileSync(segMetaFile(url), 'utf-8'));
      if (meta && typeof meta.ct === 'string' && meta.ct) contentType = meta.ct;
    } catch {
      /* ignore */
    }
    touch(f);
    return { data, contentType };
  } catch {
    return null;
  }
}

/** 写分片缓存（原子 rename，避免半文件被读到） */
export function writeCachedSeg(
  url: string,
  data: Buffer,
  contentType: string
): void {
  ensureDir();
  const f = segFile(url);
  const tmp = `${f}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(tmp, data);
    fs.writeFileSync(segMetaFile(url), JSON.stringify({ ct: contentType }));
    fs.renameSync(tmp, f);
  } catch {
    try {
      fs.rmSync(tmp, { force: true });
    } catch {
      /* ignore */
    }
  }
}

export function deleteCachedSeg(url: string): void {
  try {
    fs.rmSync(segFile(url), { force: true });
  } catch {
    /* ignore */
  }
  try {
    fs.rmSync(segMetaFile(url), { force: true });
  } catch {
    /* ignore */
  }
}

export function readCachedList(key: string): string | null {
  ensureDir();
  const f = listFile(key);
  if (!fresh(f, LIST_TTL_MS)) return null;
  try {
    touch(f);
    return fs.readFileSync(f, 'utf-8');
  } catch {
    return null;
  }
}

export function writeCachedList(key: string, content: string): void {
  ensureDir();
  const f = listFile(key);
  const tmp = `${f}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(tmp, content);
    fs.renameSync(tmp, f);
  } catch {
    try {
      fs.rmSync(tmp, { force: true });
    } catch {
      /* ignore */
    }
  }
}

/** 播放列表附带的分片索引（供看完精确清除）：{ segs: string[] } */
export function writeCachedIdx(key: string, segUrls: string[]): void {
  ensureDir();
  try {
    fs.writeFileSync(idxFile(key), JSON.stringify({ segs: segUrls }));
  } catch {
    /* ignore */
  }
}

function readCachedIdx(key: string): string[] {
  try {
    const o = JSON.parse(fs.readFileSync(idxFile(key), 'utf-8'));
    return Array.isArray(o?.segs) ? o.segs.filter((s: unknown) => typeof s === 'string') : [];
  } catch {
    return [];
  }
}

/** 精确清除：播放列表＋其索引到的全部分片（播放页关闭/切集时 keepalive 调用） */
export function deleteCachedList(key: string): number {
  let n = 0;
  for (const u of readCachedIdx(key)) {
    try {
      fs.rmSync(segFile(u), { force: true });
      n++;
    } catch {
      /* ignore */
    }
    try {
      fs.rmSync(segMetaFile(u), { force: true });
    } catch {
      /* ignore */
    }
  }
  try {
    fs.rmSync(listFile(key), { force: true });
  } catch {
    /* ignore */
  }
  try {
    fs.rmSync(idxFile(key), { force: true });
  } catch {
    /* ignore */
  }
  return n;
}

let lastSweep = 0;
/** 采样清扫：最多 10 分钟跑一次（TTL 过期＋总量 LRU） */
export function sweepProxyCacheMaybe(): void {
  const now = Date.now();
  if (now - lastSweep < 10 * 60 * 1000) return;
  lastSweep = now;
  try {
    sweepProxyCache();
  } catch (e) {
    console.warn('[proxy-cache] sweep failed:', (e as Error)?.message || e);
  }
}

function sweepProxyCache(): void {
  ensureDir();
  let files: { p: string; mtime: number; size: number; seg: boolean }[];
  try {
    files = fs
      .readdirSync(DIR)
      .map((name) => {
        const p = path.join(DIR, name);
        try {
          const st = fs.statSync(p);
          if (!st.isFile()) return null;
          const seg = name.startsWith('s-') && name.endsWith('.bin');
          const list = name.startsWith('l-') && name.endsWith('.m3u8');
          if (!seg && !list) return null;
          return { p, mtime: st.mtimeMs, size: st.size, seg };
        } catch {
          return null;
        }
      })
      .filter((x) => x !== null) as {
      p: string;
      mtime: number;
      size: number;
      seg: boolean;
    }[];
  } catch {
    return;
  }
  const now = Date.now();
  // 1) TTL 过期
  for (const f of files) {
    const ttl = f.seg ? SEG_TTL_MS : LIST_TTL_MS;
    if (now - f.mtime > ttl) {
      try {
        fs.rmSync(f.p, { force: true });
      } catch {
        /* ignore */
      }
      f.size = 0;
    }
  }
  // 2) 总量 LRU（按 mtime 从旧到新删）
  let total = files.reduce((s, f) => s + f.size, 0);
  if (total <= MAX_BYTES) return;
  files.sort((a, b) => a.mtime - b.mtime);
  for (const f of files) {
    if (total <= MAX_BYTES) break;
    if (f.size === 0) continue;
    try {
      fs.rmSync(f.p, { force: true });
      total -= f.size;
    } catch {
      /* ignore */
    }
  }
}
