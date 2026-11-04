/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { getAvailableApiSites } from '@/lib/config';
import { db } from '@/lib/db';

export interface MissavSource {
  key: string;
  name: string;
  api: string;
}

/**
 * 找出 missav 采集源：只认 key/api 里带 missav 关键字（标准建法 key=missav）。
 * 注意：故意不用分类名探测——「中文字幕」「新作上市」这类名字在普通站里遍地都是，
 * 模糊匹配会把正常源误圈进 MissAV 频道。没命中就返回空，频道页会提示去加源。
 */
export async function getMissavSources(): Promise<MissavSource[]> {
  try {
    const cachedData = await db.getGlobalValue('missav');
    if (cachedData !== null) {
      const cached: MissavSource[] = cachedData ? JSON.parse(cachedData) : [];
      if (Array.isArray(cached)) return cached;
    }

    const allSources = await getAvailableApiSites();
    const result = allSources
      .filter(
        (s) =>
          s.key.toLowerCase().includes('missav') ||
          (s.api || '').toLowerCase().includes('missav')
      )
      .map((s) => ({ key: s.key, name: s.name, api: s.api }));
    await db.setGlobalValue('missav', JSON.stringify(result));
    return result;
  } catch (error) {
    console.error('获取 missav 视频源失败:', error);
    throw error;
  }
}
