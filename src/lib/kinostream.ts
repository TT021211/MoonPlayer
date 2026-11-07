/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { getAvailableApiSites } from '@/lib/config';
import { db } from '@/lib/db';

export interface KinostreamSource {
  key: string;
  name: string;
  api: string;
}

/**
 * 找出 kinostream 采集源：只认 key/api 里带 kinostream 关键字
 * （标准建法 key=kinostream）。没命中就返回空，频道页会提示去加源。
 */
export async function getKinostreamSources(): Promise<KinostreamSource[]> {
  try {
    const cachedData = await db.getGlobalValue('kinostream');
    if (cachedData !== null) {
      const cached: KinostreamSource[] = cachedData
        ? JSON.parse(cachedData)
        : [];
      if (Array.isArray(cached)) return cached;
    }

    const allSources = await getAvailableApiSites();
    const result = allSources
      .filter(
        (s) =>
          s.key.toLowerCase().includes('kinostream') ||
          (s.api || '').toLowerCase().includes('kinostream')
      )
      .map((s) => ({ key: s.key, name: s.name, api: s.api }));
    await db.setGlobalValue('kinostream', JSON.stringify(result));
    return result;
  } catch (error) {
    console.error('获取 kinostream 视频源失败:', error);
    throw error;
  }
}
