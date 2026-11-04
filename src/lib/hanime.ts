/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { API_CONFIG, getAvailableApiSites } from '@/lib/config';
import { db } from '@/lib/db';
import { isHanimeTypeName } from '@/lib/hanime.client';
import { parseJsonLosslessIntegers } from '@/lib/json';

export interface HanimeSource {
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
 * 找出 hanime 采集源：
 * 1. key 或 api 里带 hanime 关键字 → 直接命中（最常见：key=hanime1）；
 * 2. 否则调 `?ac=list` 看 class 里有没有裏番/Cosplay 等 hanime 分类。
 * 结果缓存到 db global `hanime`（仿 duanju.ts），后台改源后调 /api/admin/reload 或重启即刷新。
 */
export async function getHanimeSources(): Promise<HanimeSource[]> {
  try {
    const cachedData = await db.getGlobalValue('hanime');
    if (cachedData !== null) {
      const cached: HanimeSource[] = cachedData ? JSON.parse(cachedData) : [];
      // 空数组也视为有效缓存（= 已确认没有 hanime 源，避免每次都全网探测）
      if (Array.isArray(cached)) return cached;
    }

    const allSources = await getAvailableApiSites();
    if (allSources.length === 0) {
      await db.setGlobalValue('hanime', JSON.stringify([]));
      return [];
    }

    // 快路径：key/api 命中
    const keywordHit = allSources.filter(
      (s) =>
        s.key.toLowerCase().includes('hanime') ||
        (s.api || '').toLowerCase().includes('hanime')
    );
    if (keywordHit.length > 0) {
      const result = keywordHit.map((s) => ({ key: s.key, name: s.name, api: s.api }));
      await db.setGlobalValue('hanime', JSON.stringify(result));
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
          const hit = data.class.find((item) => isHanimeTypeName(item.type_name || ''));
          if (hit) return { key: source.key, name: source.name, api: source.api };
        }
        return null;
      } catch {
        return null;
      }
    });

    const results = await Promise.all(checkPromises);
    const hanimeSources = results.filter((r): r is HanimeSource => r !== null);
    console.log(`找到 ${hanimeSources.length} 个 hanime 采集源`);
    await db.setGlobalValue('hanime', JSON.stringify(hanimeSources));
    return hanimeSources;
  } catch (error) {
    console.error('获取 hanime 视频源失败:', error);
    throw error;
  }
}
