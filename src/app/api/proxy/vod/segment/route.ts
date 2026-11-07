/* eslint-disable no-console,@typescript-eslint/no-explicit-any */

import { NextResponse } from 'next/server';

import { getConfig } from '@/lib/config';
import {
  deleteCachedSeg,
  readCachedSeg,
  sweepProxyCacheMaybe,
  writeCachedSeg,
} from '@/lib/server/proxy-cache';
import { validateProxyUrlServerSide } from '@/lib/server/ssrf';
import { buildProxyStreamHeaders, buildUpstreamReferer } from '@/lib/server/proxy-headers';

export const runtime = 'nodejs';

const SEG_CACHE_MAX_BYTES = 256 * 1024 * 1024; // 单个分片缓存上限（防内存爆，HLS 分片远小于此值）

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

    // 落盘缓存命中：VPS 直接给，不再回源（倒回去看、重播都走磁盘）
    const hit = readCachedSeg(decodedUrl);
    if (hit) {
      const hitHeaders = buildProxyStreamHeaders(hit.contentType);
      hitHeaders.set('Cache-Control', 'no-cache');
      hitHeaders.set('X-Proxy-Cache', 'HIT');
      return new Response(hit.data as unknown as BodyInit, {
        status: 200,
        headers: hitHeaders,
      });
    }

    response = await fetch(decodedUrl, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': buildUpstreamReferer(source, decodedUrl),
      },
    });
    if (!response.ok) {
      return NextResponse.json({ error: 'Failed to fetch segment' }, { status: 500 });
    }

    const headers = buildProxyStreamHeaders(
      response.headers.get('Content-Type') || 'video/mp2t',
      response.headers.get('content-length')
    );
    headers.set('X-Proxy-Cache', 'MISS');

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
