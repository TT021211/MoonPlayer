/* eslint-disable no-console,@typescript-eslint/no-explicit-any */

import { NextResponse } from 'next/server';

import { getConfig } from '@/lib/config';
import {
  deleteCachedSeg,
  readCachedSeg,
  sweepProxyCacheMaybe,
  writeCachedSeg,
} from '@/lib/server/proxy-cache';
import { fetchUpstreamRetry } from '@/lib/server/fetch-retry';
import { validateProxyUrlServerSide } from '@/lib/server/ssrf';
import { buildProxyStreamHeaders, buildUpstreamReferer } from '@/lib/server/proxy-headers';

export const runtime = 'nodejs';

const SEG_CACHE_MAX_BYTES = 256 * 1024 * 1024; // 单个分片缓存上限（防内存爆，HLS 分片远小于此值）

/** 解析客户端 Range 头（bytes=A-B / A- / -S），total 为完整长度 */
function parseRangeHeader(
  header: string | null,
  total: number
): { start: number; end: number } | null {
  if (!header || total <= 0) return null;
  const m = header.trim().match(/^bytes=(\d*)-(\d*)$/);
  if (!m || (m[1] === '' && m[2] === '')) return null;
  if (m[1] === '') {
    const suffix = parseInt(m[2], 10);
    if (!Number.isFinite(suffix) || suffix <= 0) return null;
    return { start: Math.max(0, total - suffix), end: total - 1 };
  }
  const start = parseInt(m[1], 10);
  if (!Number.isFinite(start) || start < 0 || start >= total) return null;
  let end = m[2] === '' ? total - 1 : parseInt(m[2], 10);
  if (!Number.isFinite(end) || end < start) return null;
  return { start, end: Math.min(end, total - 1) };
}

export async function DELETE(request: Request) {
  try {
    const { searchParams } = new URL(request.url);
    const url = searchParams.get('url');
    if (!url) {
      return NextResponse.json({ error: 'Missing url' }, { status: 400 });
    }
    deleteCachedSeg(decodeURIComponent(url));
    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json(
      { error: '清除缓存失败', details: (error as Error).message },
      { status: 500 }
    );
  }
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const url = searchParams.get('url');
  const source = searchParams.get('source');

  if (!url) {
    return NextResponse.json({ error: 'Missing url' }, { status: 400 });
  }

  if (!source) {
    return NextResponse.json({ error: 'Missing source' }, { status: 400 });
  }

  // 定义直链播放模式常量
  const DIRECT_PLAY_SOURCE = 'directplay';

  // 直链播放模式：跳过源站配置检查，直接代理
  if (source !== DIRECT_PLAY_SOURCE) {
    // 检查该视频源是否启用了代理模式
    const config = await getConfig();
    const videoSource = config.SourceConfig?.find((s: any) => s.key === source);

    if (!videoSource) {
      return NextResponse.json({ error: 'Source not found' }, { status: 404 });
    }

    if (!videoSource.proxyMode) {
      return NextResponse.json({ error: 'Proxy mode not enabled for this source' }, { status: 403 });
    }
  }

  let response: Response | null = null;
  let reader: ReadableStreamDefaultReader<Uint8Array> | null = null;

  try {
    const decodedUrl = decodeURIComponent(url);

    // 安全校验：防 SSRF 拦截请求内网或非法 URL (强制检查所有代理请求)
    const isSafeUrl = await validateProxyUrlServerSide(decodedUrl);
    if (!isSafeUrl) {
      return NextResponse.json({ error: 'Proxy request to local or invalid network is forbidden' }, { status: 403 });
    }

    sweepProxyCacheMaybe();

    const clientRange = request.headers.get('range');

    // 落盘缓存命中：VPS 直接给，不再回源（倒回去看、重播都走磁盘）；
    // 带 Range 时从完整缓存里切片回 206（BYTERANGE 分片必需）
    const hit = readCachedSeg(decodedUrl);
    if (hit) {
      const total = hit.data.length;
      const hitHeaders = buildProxyStreamHeaders(hit.contentType);
      hitHeaders.set('Cache-Control', 'no-cache');
      hitHeaders.set('X-Proxy-Cache', 'HIT');
      if (clientRange) {
        const r = parseRangeHeader(clientRange, total);
        if (!r) {
          hitHeaders.set('Content-Range', `bytes */${total}`);
          return new Response('Range Not Satisfiable', { status: 416, headers: hitHeaders });
        }
        hitHeaders.set('Content-Range', `bytes ${r.start}-${r.end}/${total}`);
        hitHeaders.set('Content-Length', String(r.end - r.start + 1));
        return new Response(hit.data.subarray(r.start, r.end + 1) as unknown as BodyInit, {
          status: 206,
          headers: hitHeaders,
        });
      }
      return new Response(hit.data as unknown as BodyInit, {
        status: 200,
        headers: hitHeaders,
      });
    }

    const upHeaders: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': buildUpstreamReferer(source, decodedUrl),
    };
    // Range 透传上游（BYTERANGE 分片必需）；上游回的分片不缓存，防半包污染
    if (clientRange) upHeaders['Range'] = clientRange;
    response = await fetchUpstreamRetry(decodedUrl, upHeaders);
    if (!response.ok) {
      // 记上游 host＋路径（不记 token 查询串），方便定位是墙/拒连还是地址过期
      try {
        const u = new URL(decodedUrl);
        console.warn(`[proxy-seg] upstream ${response.status} host=${u.host} path=${u.pathname.slice(0, 100)}`);
      } catch {
        /* ignore */
      }
      return NextResponse.json({ error: 'Failed to fetch segment' }, { status: 500 });
    }

    const headers = buildProxyStreamHeaders(
      response.headers.get('Content-Type') || 'video/mp2t',
      response.headers.get('content-length')
    );
    headers.set('X-Proxy-Cache', 'MISS');

    // 上游回 206 分片：直接透传（状态＋Range 头原样带回），不写缓存
    if (response.status === 206) {
      const upstreamRange =
        response.headers.get('content-range') ||
        response.headers.get('Content-Range');
      if (upstreamRange) headers.set('Content-Range', upstreamRange);
      headers.delete('Content-Length');
      const upstreamLen =
        response.headers.get('content-length') ||
        response.headers.get('Content-Length');
      if (upstreamLen) headers.set('Content-Length', upstreamLen);
      return new Response(response.body, { status: 206, headers });
    }

    // 客户端要 Range 但上游给了整包：缓冲后切片回 206，整包照常落盘
    if (clientRange) {
      const full = Buffer.from(await response.arrayBuffer());
      if (full.length > 0 && full.length <= SEG_CACHE_MAX_BYTES) {
        writeCachedSeg(
          decodedUrl,
          full,
          response.headers.get('Content-Type') || 'video/mp2t'
        );
      }
      const r = parseRangeHeader(clientRange, full.length);
      if (!r) {
        headers.set('Content-Range', `bytes */${full.length}`);
        return new Response('Range Not Satisfiable', { status: 416, headers });
      }
      headers.set('Content-Range', `bytes ${r.start}-${r.end}/${full.length}`);
      headers.set('Content-Length', String(r.end - r.start + 1));
      headers.set('X-Proxy-Cache', 'MISS');
      return new Response(full.subarray(r.start, r.end + 1) as unknown as BodyInit, {
        status: 206,
        headers,
      });
    }

    // 使用流式传输，避免占用内存；同时边推边存一份到磁盘（首遍看完即缓存）
    let isCancelled = false;
    const segContentType = response.headers.get('Content-Type') || 'video/mp2t';
    const cacheChunks: Uint8Array[] = [];
    let cacheLen = 0;
    let cacheOverflow = false;

    const stream = new ReadableStream({
      start(controller) {
        if (!response?.body) {
          controller.close();
          return;
        }

        reader = response.body.getReader();

        function pump() {
          if (isCancelled || !reader) {
            return;
          }

          reader.read().then(({ done, value }) => {
            if (isCancelled) {
              return;
            }

            if (done) {
              controller.close();
              cleanup();
              // 整包收齐且客户端没中途取消：落盘
              if (!isCancelled && !cacheOverflow && cacheChunks.length > 0) {
                try {
                  writeCachedSeg(decodedUrl, Buffer.concat(cacheChunks), segContentType);
                } catch {
                  /* ignore */
                }
              }
              return;
            }

            controller.enqueue(value);
            // 边推边存（单包超 256MB 则放弃缓存，只透传）
            if (!cacheOverflow) {
              if (cacheLen + value.length > SEG_CACHE_MAX_BYTES) {
                cacheOverflow = true;
                cacheChunks.length = 0;
              } else {
                cacheChunks.push(value);
                cacheLen += value.length;
              }
            }
            pump();
          }).catch((error) => {
            if (!isCancelled) {
              controller.error(error);
              cleanup();
            }
          });
        }

        function cleanup() {
          if (reader) {
            try {
              reader.releaseLock();
            } catch (e) {
              // reader 可能已经被释放，忽略错误
            }
            reader = null;
          }
        }

        pump();
      },
      cancel() {
        isCancelled = true;
        // 当流被取消时，确保释放所有资源
        if (reader) {
          try {
            reader.releaseLock();
          } catch (e) {
            // reader 可能已经被释放，忽略错误
          }
          reader = null;
        }

        if (response?.body) {
          try {
            response.body.cancel();
          } catch (e) {
            // 忽略取消时的错误
          }
        }
      }
    });

    return new Response(stream, { headers });
  } catch (error) {
    // 确保在错误情况下也释放资源
    if (reader) {
      try {
        (reader as ReadableStreamDefaultReader<Uint8Array>).releaseLock();
      } catch (e) {
        // 忽略错误
      }
    }

    if (response?.body) {
      try {
        response.body.cancel();
      } catch (e) {
        // 忽略错误
      }
    }

    // 片源服务器拒连（常驻防火墙白名单）：给明确提示而不是裸 500
    const segErr = String((error as any)?.cause || error || '');
    if (/ECONNREFUSED|EHOSTUNREACH|ENETUNREACH/.test(segErr)) {
      return NextResponse.json(
        { error: '片源服务器拒绝当前网络连接，换一部试试' },
        { status: 502 }
      );
    }
    return NextResponse.json({ error: 'Failed to fetch segment' }, { status: 500 });
  }
}
