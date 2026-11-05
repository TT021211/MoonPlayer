/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { NextRequest, NextResponse } from 'next/server';

import { API_CONFIG, getCacheTime } from '@/lib/config';
import { getMissavSources } from '@/lib/missav';
import { MISSAV_CATS } from '@/lib/missav.client';
import { parseJsonLosslessIntegers } from '@/lib/json';

export const runtime = 'nodejs';

interface CmsClassResponse {
  class?: Array<{
    type_id: string | number;
    type_name: string;
    type_pid?: string | number;
    group?: string;
  }>;
}

/**
 * 里番分类：优先用上游 `?ac=list` 返回的 class（采集端升级加分类时自动跟进），
 * 失败/为空时回退到内置 MISSAV_CATS（13 个，type_id 直接当 t 用）。
 * 注意：这里故意不做黄词过滤——里番频道本身就是 R18，
 * 是否过滤交给全局 DisableYellowFilter（用户已选全局关闭）。
 */
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const sourceKey = searchParams.get('source');

  if (!sourceKey) {
    return NextResponse.json({ code: 400, message: '缺少参数: source', data: [] }, { status: 400 });
  }

  try {
    const sources = await getMissavSources();
    const targetSource = sources.find((s) => s.key === sourceKey);
    if (!targetSource) {
      return NextResponse.json(
        { code: 404, message: `未找到 missav 采集源: ${sourceKey}`, data: [] },
        { status: 404 }
      );
    }

    let categories = MISSAV_CATS.map((c) => ({
      id: String(c.type_id),
      name: c.type_name,
      pid: '0',
    }));

    try {
      const response = await fetch(`${targetSource.api}?ac=list`, {
        headers: API_CONFIG.search.headers,
        signal: AbortSignal.timeout(120000), // 中转站 render 慢，直连站 10 秒足够
      });
      if (response.ok) {
        const data = parseJsonLosslessIntegers<CmsClassResponse>(await response.text());
        if (data.class && Array.isArray(data.class) && data.class.length > 0) {
          categories = data.class.map((item) => ({
            id: String(item.type_id),
            name: item.type_name || String(item.type_id),
            pid: String(item.type_pid ?? 0),
            group: item.group || '',
          }));
        }
      }
    } catch (e) {
      console.warn('missav 上游分类拉取失败，回退内置分类:', (e as Error).message);
    }

    const defaultCategory = categories[0] || null;
    const cacheTime = await getCacheTime();
    return NextResponse.json(
      { code: 200, message: '获取成功', data: categories, defaultCategory },
      { headers: { 'Cache-Control': `public, max-age=${cacheTime}, s-maxage=${cacheTime}` } }
    );
  } catch (error) {
    console.error('获取 missav 分类失败:', error);
    return NextResponse.json(
      { code: 500, message: '获取 missav 分类失败', data: [], error: (error as Error).message },
      { status: 500 }
    );
  }
}
