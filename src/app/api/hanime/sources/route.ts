/* eslint-disable @typescript-eslint/no-explicit-any,no-console */

import { NextResponse } from 'next/server';

import { getCacheTime } from '@/lib/config';
import { getHanimeSources } from '@/lib/hanime';

export const runtime = 'nodejs';

export async function GET() {
  try {
    const sources = await getHanimeSources();
    const cacheTime = await getCacheTime();
    return NextResponse.json(
      { code: 200, message: '获取成功', data: sources },
      { headers: { 'Cache-Control': `public, max-age=${cacheTime}, s-maxage=${cacheTime}` } }
    );
  } catch (error) {
    console.error('获取 hanime 视频源失败:', error);
    return NextResponse.json(
      { code: 500, message: '获取 hanime 视频源失败', error: (error as Error).message },
      { status: 500 }
    );
  }
}
