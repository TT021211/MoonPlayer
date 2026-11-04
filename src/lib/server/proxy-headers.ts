/**
 * 代理接口共享工具函数
 * 用于构建标准化的 CORS 响应头，避免各代理路由中的重复代码。
 */

/**
 * 构建标准的代理流式响应头 (用于 ts 分片、密钥、二进制流等)
 * 包含 CORS、Accept-Ranges 和 Content-Length 等标准头。
 */
export function buildProxyStreamHeaders(
  contentType: string,
  contentLength?: string | null
): Headers {
  const headers = new Headers();
  headers.set('Content-Type', contentType);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Range, Origin, Accept');
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
  if (contentLength) {
    headers.set('Content-Length', contentLength);
  }
  return headers;
}

/**
 * 上游 Referer：默认用被代理 URL 自身（原有行为，大部分源不校验）。
 * 部分源强制校验 Referer 域名（如 MissAV 的 surrit CDN 只认 missav.ai），
 * 这里按源 key 覆盖。不确定的新源先用 curl 测三组
 * （自身/空/上游站）再决定加不加。
 */
const UPSTREAM_REFERER_OVERRIDE: Record<string, string> = {
  missav: 'https://missav.ai/',
};

export function buildUpstreamReferer(
  source: string | null,
  decodedUrl: string
): string {
  if (source && UPSTREAM_REFERER_OVERRIDE[source]) {
    return UPSTREAM_REFERER_OVERRIDE[source];
  }
  return decodedUrl;
}

/**
 * 构建标准的代理 M3U8 播放列表响应头
 */
export function buildProxyM3u8Headers(contentType?: string): Headers {
  const headers = new Headers();
  headers.set('Content-Type', contentType || 'application/vnd.apple.mpegurl');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Range, Origin, Accept');
  headers.set('Cache-Control', 'no-cache');
  headers.set('Access-Control-Expose-Headers', 'Content-Length, Content-Range');
  return headers;
}
