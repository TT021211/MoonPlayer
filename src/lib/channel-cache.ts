import { SearchResult } from '@/lib/types';

// 自建源频道列表/详情进程内缓存：频道翻页、切集、刷新不再每次回源 Hub。
// 列表 5 分钟（翻页高频），详情 10 分钟（hanime1 HLS 地址确定性拼串可安全缓存；
// 直传站 m3u8 可能短效，详情 TTL 保守取 10 分钟，播放失败前端重试即回源）。
const LIST_TTL_MS = 5 * 60 * 1000;
const DETAIL_TTL_MS = 10 * 60 * 1000;
const MAX_SIZE = 2000;

interface Entry<T> {
  exp: number;
  data: T;
}

const listCache = new Map<string, Entry<unknown>>();
const detailCache = new Map<string, Entry<SearchResult>>();

function get<T>(m: Map<string, Entry<unknown>>, key: string): T | null {
  const e = m.get(key);
  if (!e) return null;
  if (e.exp <= Date.now()) {
    m.delete(key);
    return null;
  }
  return e.data as T;
}

function set(m: Map<string, Entry<unknown>>, key: string, data: unknown, ttl: number) {
  if (m.size > MAX_SIZE) m.clear();
  m.set(key, { exp: Date.now() + ttl, data });
}

export function getCachedChannelList<T>(key: string): T | null {
  return get<T>(listCache, key);
}

export function setCachedChannelList<T>(key: string, data: T) {
  set(listCache, key, data, LIST_TTL_MS);
}

export function getCachedChannelDetail(source: string, id: string): SearchResult | null {
  return get(detailCache, `${source}::${id}`);
}

export function setCachedChannelDetail(source: string, id: string, data: SearchResult) {
  set(detailCache, `${source}::${id}`, data, DETAIL_TTL_MS);
}
