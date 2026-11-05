// Cloudflare Workers 自定义入口 —— wrangler.toml 的 main 指向本文件。
//
// OpenNext 生成的 .open-next/worker.js 只导出 fetch，而：
//   * Durable Object 类必须由入口 export 出去才会被注册；
//   * Cloudflare 的定时任务要在入口 export 一个 scheduled。
// 所以这里把 OpenNext 的 fetch 复用过来，再补上上面两样。
//
// 参考：https://opennext.js.org/cloudflare/howtos/custom-worker

// @ts-ignore 构建期由 opennextjs-cloudflare 生成
import openNextWorker from './.open-next/worker.js';
import type { DurableObjectNamespace, ExecutionContext } from './src/worker/cf-runtime';

// 转发 OpenNext 自带的具名导出（DOQueueHandler / DOShardedTagCache / BucketCachePurge）。
// 当前 open-next.config.ts 用的是 dummy 缓存/队列，暂时用不到；但一旦换成真缓存，
// 这些类必须在入口注册，所以这里原样转发。
// @ts-ignore 构建期由 opennextjs-cloudflare 生成
export * from './.open-next/worker.js';

// （观影室已移除：不再导出 WatchRoomHub Durable Object）

interface Env {
  CRON_PASSWORD?: string;
  [key: string]: unknown;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return openNextWorker.fetch(request, env, ctx);
  },

  // 定时任务：直接内部打一次 /api/cron/<password>。
  // wrangler.toml 里 CRON_WAIT_FOR_COMPLETION="true"，路由会等任务跑完再返回，
  // 所以这里 await（不要用 ctx.waitUntil —— 那是"先返回后台继续"的语义）。
  async scheduled(_event: unknown, env: Env, ctx: ExecutionContext): Promise<void> {
    const password = env.CRON_PASSWORD || 'mtvpls';
    const url = new URL(`/api/cron/${password}`, 'https://internal.invalid');
    await openNextWorker.fetch(new Request(url), env, ctx);
  },
};
