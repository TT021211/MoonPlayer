/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { getAvailableApiSites } from '@/lib/config';
import { db } from '@/lib/db';

export interface AqdltSource {
  key: string;
  name: string;
  api: string;
}

/**
 * 找出 aqdlt 专用源：只认 key/api 里带 aqdlt 关键字（标准建法 key=aqdlt）。
 * 注意：本站分类名（中文字幕/学生/制服…）在普通站里遍地都是，绝不能用分类名探测，
 * 否则会把正常源误圈进频道。没命中就返回空，频道页会提示去加源。
 */
export async function getAqdltSources(): Promise<AqdltSource[]> {
  try {
    const cachedData = await db.getGlobalValue('aqdlt');
    if (cachedData !== null) {
      const cached: AqdltSource[] = cachedData ? JSON.parse(cachedData) : [];
      if (Array.isArray(cached)) return cached;
    }

    const allSources = await getAvailableApiSites();
    const result = allSources
      .filter(
        (s) =>
          s.key.toLowerCase().includes('aqdlt') ||
          (s.api || '').toLowerCase().includes('aqdlt')
      )
      .map((s) => ({ key: s.key, name: s.name, api: s.api }));
    await db.setGlobalValue('aqdlt', JSON.stringify(result));
    return result;
  } catch (error) {
    console.error('获取 aqdlt 视频源失败:', error);
    throw error;
  }
}
