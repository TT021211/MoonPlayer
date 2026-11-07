'use client';

import { useEffect } from 'react';

import { initStartupCacheCleanup } from '@/lib/startup/cacheCleanup';

// 启动时初始化推荐缓存模块。
export default function StartupCacheCleanup() {
  useEffect(() => {
    initStartupCacheCleanup();
  }, []);
  return null;
}
