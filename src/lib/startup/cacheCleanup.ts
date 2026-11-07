import { initRecommendationCacheModule } from '@/lib/recommendations/cache';

let startupCacheCleanupInitialized = false;

export function initStartupCacheCleanup(): void {
  if (typeof window === 'undefined' || startupCacheCleanupInitialized) {
    return;
  }

  startupCacheCleanupInitialized = true;

  initRecommendationCacheModule();
}
