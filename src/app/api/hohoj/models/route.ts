/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { NextRequest, NextResponse } from 'next/server';

import { API_CONFIG, getCacheTime } from '@/lib/config';
import { getHohojSources } from '@/lib/hohoj';
import { parseJsonLosslessIntegers } from '@/lib/json';

export const runtime = 'nodejs';

interface CmsModelItem {
  vod_id: string | number;
  vod_name: string;
  vod_pic?: string;
}

interface CmsModelResponse {
  list?: CmsModelItem[];
  total?: number;
  page?: number;
  pagecount?: number;
}

/* hohoj 女优墙：order=popular（最熱門）| views（最多觀看），pg 翻页 */
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const sourceKey = searchParams.get('source');
  const order = searchParams.get('order') === 'views' ? 'views' : 'popular';
  const page = Math.max(1, parseInt(searchParams.get('page') || '1', 10) || 1);

  if (!sourceKey) {
    return NextResponse.json({ code: 400, message: '缺少参数: source', data: [] }, { status: 400 });
  }

  try {
    const sources = await getHohojSources();
    const targetSource = sources.find((s) => s.key === sourceKey);
    if (!targetSource) {
      return NextResponse.json(
        { code: 404, message: `未找到 hohoj 采集源: ${sourceKey}`, data: [] },
        { status: 404 }
      );
    }

    const response = await fetch(
      `${targetSource.api}?ac=models&order=${order}&pg=${page}`,
      { headers: API_CONFIG.search.headers, signal: AbortSignal.timeout(30000) }
    );
    if (!response.ok) throw new Error('获取 hohoj 女优列表失败');

    const modelData = parseJsonLosslessIntegers<CmsModelResponse>(await response.text());
    const results = (modelData.list || []).map((item) => ({
      id: String(item.vod_id).replace(/^model-/, ''),
      name: (item.vod_name || '').trim(),
      pic: item.vod_pic || '',
    }));

    const cacheTime = await getCacheTime();
    return NextResponse.json(
      {
        code: 200,
        message: '获取成功',
        data: results,
        total: modelData.total || 0,
        page: modelData.page || page,
        pageCount: modelData.pagecount || (results.length > 0 ? page + 1 : page),
      },
      { headers: { 'Cache-Control': `public, max-age=${cacheTime}, s-maxage=${cacheTime}` } }
    );
  } catch (error) {
    console.error('获取 hohoj 女优列表失败:', error);
    return NextResponse.json(
      { code: 500, message: '获取 hohoj 女优列表失败', data: [], error: (error as Error).message },
      { status: 500 }
    );
  }
}
