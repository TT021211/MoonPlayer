/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { NextRequest, NextResponse } from 'next/server';

import { API_CONFIG, getCacheTime } from '@/lib/config';
import { getHanimeSources } from '@/lib/hanime';
import { parseJsonLosslessIntegers } from '@/lib/json';
import { SearchResult } from '@/lib/types';
import { cleanHtmlTags } from '@/lib/utils';

export const runtime = 'nodejs';

interface CmsVideoItem {
  vod_id: string | number;
  vod_name: string;
  vod_pic?: string;
  vod_remarks?: string;
  vod_year?: string;
  vod_play_url?: string;
  vod_class?: string;
  vod_content?: string;
  vod_douban_id?: number;
  type_name?: string;
}

interface CmsVideoResponse {
  list?: CmsVideoItem[];
  total?: number;
  page?: number;
  pagecount?: number;
}

/**
 * 里番频道内搜索：只查 hanime 源 (`?ac=list&wd=&pg=`)，
 * 与全站聚合搜索隔离，避免 R18 污染普通搜索（聚合搜索是否混入由 SourceConfig 决定）。
 * 故意不做黄词过滤。
 */
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const sourceKey = searchParams.get('source');
  const keyword = (searchParams.get('keyword') || searchParams.get('wd') || '').trim();
  const page = Math.max(1, parseInt(searchParams.get('page') || '1', 10) || 1);

  if (!sourceKey) {
    return NextResponse.json({ code: 400, message: '缺少参数: source', data: [] }, { status: 400 });
  }
  if (!keyword) {
    return NextResponse.json({ code: 400, message: '缺少参数: keyword', data: [] }, { status: 400 });
  }

  try {
    const sources = await getHanimeSources();
    const targetSource = sources.find((s) => s.key === sourceKey);
    if (!targetSource) {
      return NextResponse.json(
        { code: 404, message: `未找到 hanime 采集源: ${sourceKey}`, data: [] },
        { status: 404 }
      );
    }

    const response = await fetch(
      `${targetSource.api}?ac=videolist&wd=${encodeURIComponent(keyword)}&pg=${page}`,
      { headers: API_CONFIG.search.headers, signal: AbortSignal.timeout(30000) }
    );
    if (!response.ok) throw new Error('hanime 搜索失败');

    const videoData = parseJsonLosslessIntegers<CmsVideoResponse>(await response.text());
    const results: SearchResult[] = (videoData.list || []).map((item) => {
      const episodes: string[] = [];
      const episodesTitles: string[] = [];
      (item.vod_play_url || '').split('$$$').forEach((su) =>
        su.split('#').forEach((es) => {
          const idx = es.indexOf('$');
          if (idx <= 0) return;
          const name = es.slice(0, idx).trim();
          const url = es.slice(idx + 1).trim();
          if (name && url) {
            episodes.push(url);
            episodesTitles.push(name);
          }
        })
      );
      return {
        id: item.vod_id.toString(),
        title: (item.vod_name || '').trim().replace(/\s+/g, ' '),
        poster: item.vod_pic || '',
        year: item.vod_year ? item.vod_year.match(/\d{4}/)?.[0] || item.vod_year : 'unknown',
        episodes,
        episodes_titles: episodesTitles,
        source: targetSource.key,
        source_name: targetSource.name,
        class: item.vod_class,
        desc: cleanHtmlTags(item.vod_content || ''),
        type_name: item.type_name,
        douban_id: item.vod_douban_id,
        vod_remarks: item.vod_remarks,
      };
    });

    const cacheTime = await getCacheTime();
    return NextResponse.json(
      {
        code: 200,
        message: '获取成功',
        data: results,
        total: videoData.total || 0,
        page: videoData.page || page,
        pageCount: videoData.pagecount || (results.length > 0 ? page + 1 : page),
      },
      { headers: { 'Cache-Control': `public, max-age=${cacheTime}, s-maxage=${cacheTime}` } }
    );
  } catch (error) {
    console.error('hanime 搜索失败:', error);
    return NextResponse.json(
      { code: 500, message: 'hanime 搜索失败', data: [], error: (error as Error).message },
      { status: 500 }
    );
  }
}
