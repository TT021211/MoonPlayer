/* eslint-disable no-console */

/**
 * 上游抓取（带重试）：境外 CDN 对机房 IP 限流/抖动是常态，幂等 GET 失败就歇一下再试。
 * - 4xx（除 408/429）不重试：地址本身有问题，重试也没用，原样返回让上层处理
 * - 5xx/429/网络异常：最多重试，总等待约 0.8s + 1.6s
 */

export async function fetchUpstreamRetry(
  url: string,
  headers: Record<string, string>,
  tries = 3,
  timeoutMs = 15000
): Promise<Response> {
  let lastErr: unknown = null;
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, {
        headers,
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (res.ok) return res;
      if (
        res.status >= 400 &&
        res.status < 500 &&
        res.status !== 408 &&
        res.status !== 429
      ) {
        return res;
      }
      lastErr = new Error(`upstream http ${res.status} for ${url.slice(0, 120)}`);
      try {
        await res.arrayBuffer();
      } catch {
        /* ignore */
      }
    } catch (e) {
      lastErr = e;
    }
    if (i < tries - 1) {
      await new Promise((r) => setTimeout(r, 800 * (i + 1)));
    }
  }
  throw lastErr instanceof Error ? lastErr : new Error('fetch failed');
}
