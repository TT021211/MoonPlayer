/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { API_CONFIG, getAvailableApiSites } from '@/lib/config';
import { db } from '@/lib/db';
import { isMissavTypeName } from '@/lib/missav.client';
import { parseJsonLosslessIntegers } from '@/lib/json';

export interface MissavSource {
  key: string;
  name: string;
  api: string;
}

interface CmsClassResponse {
  class?: Array<{
    type_id: string | number;
    type_name: string;
  }>;
}

/**
 * 找出 missav 采集源：
 * 1. key 或 api 里带 missav 关键字 → 直接命中（最常见：key=missav）；
 * 2. 否则调 `?ac=list` 看 class 里有没有最新更新/無碼流出等 missav 分类。
 * 结果缓存到 db global `missav`。后台改源后自动清（admin/source）。
 */
export async function getMissavSources(): Promise<MissavSource[]> {
  try {
    const cachedData = await db.getGlobalValue('missav');
    if (cachedData !== null) {
      const cached: MissavSource[] = cachedData ? JSON.parse(cachedData) : [];
      if (Array.isArray(cached)) return cached;
    }

    const allSources = await getAvailableApiSites();
    if (allSources.length === 0) {
      await db.setGlobalValue('missav', JSON.stringify([]));
      return [];
    }

    // 快路径：key/api 命中
    const keywordHit = allSources.filter(
      (s) =>
        s.key.toLowerCase().includes('missav') ||
        (s.api || '').toLowerCase().includes('missav')
    );
    if (keywordHit.length > 0) {
      const result = keywordHit.map((s) => ({ key: s.key, name: s.name, api: s.api }));
      await db.setGlobalValue('missav', JSON.stringify(result));
      return result;
    }

    // 慢路径：逐个调 ?ac=list 看分类
    const checkPromises = allSources.map(async (source) => {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        const response = await fetch(`${source.api}?ac=list`, {
          headers: API_CONFIG.search.headers,
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (!response.ok) return null;
        const data = parseJsonLosslessIntegers<CmsClassResponse>(await response.text());
        if (data.class && Array.isArray(data.class)) {
          const hit = data.class.find((item) => isMissavTypeName(item.type_name || ''));
          if (hit) return { key: source.key, name: source.name, api: source.api };
        }
        return null;
      } catch {
        return null;
      }
    });

    const results = await Promise.all(checkPromises);
    const missavSources = results.filter((r): r is MissavSource => r !== null);
    console.log(`找到 ${missavSources.length} 个 missav 采集源`);
    await db.setGlobalValue('missav', JSON.stringify(missavSources));
    return missavSources;
  } catch (error) {
    console.error('获取 missav 视频源失败:', error);
    throw error;
  }
}
