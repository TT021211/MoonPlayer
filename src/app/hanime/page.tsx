/* eslint-disable @typescript-eslint/no-explicit-any, react-hooks/exhaustive-deps */
'use client';

import { ArrowLeft, ChevronUp, Loader2, Search } from 'lucide-react';
import Link from 'next/link';
import { Suspense, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { HANIME_STATE_KEY } from '@/lib/hanime.client';
import { SearchResult } from '@/lib/types';

import CategoryBreadcrumb, {
  buildCrumbGroups,
} from '@/components/CategoryBreadcrumb';
import PageLayout from '@/components/PageLayout';
import VideoCard from '@/components/VideoCard';

interface HanimeSource {
  key: string;
  name: string;
  api: string;
}

interface HanimeCategory {
  id: string;
  name: string;
  pid: string;
  group?: string;
}

interface HanimeSnapshot {
  sources: HanimeSource[];
  selectedSource: string;
  categories: HanimeCategory[];
  selectedCategory: string;
  videos: SearchResult[];
  currentPage: number;
  hasMore: boolean;
  scrollTop: number;
  keyword: string;
}

const getPageScrollTop = () =>
  document.body.scrollTop || document.documentElement.scrollTop || 0;

const scrollPageTo = (top: number) => {
  document.body.scrollTop = top;
  document.documentElement.scrollTop = top;
};

const useIsomorphicLayoutEffect = typeof window === 'undefined' ? useEffect : useLayoutEffect;

const consumeSnapshot = (): HanimeSnapshot | null => {
  if (typeof window === 'undefined') return null;
  try {
    const raw = sessionStorage.getItem(HANIME_STATE_KEY);
    sessionStorage.removeItem(HANIME_STATE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as HanimeSnapshot;
    if (!parsed?.selectedSource || !Array.isArray(parsed.videos) || parsed.videos.length === 0) return null;
    return parsed;
  } catch {
    return null;
  }
};

function HanimePageClient() {
  const [sources, setSources] = useState<HanimeSource[]>([]);
  const [selectedSource, setSelectedSource] = useState('');
  const [categories, setCategories] = useState<HanimeCategory[]>([]);
  const [selectedCategory, setSelectedCategory] = useState('');
  const [videos, setVideos] = useState<SearchResult[]>([]);
  const [keyword, setKeyword] = useState('');
  const [searching, setSearching] = useState(false); // 空 = 浏览模式，非空 = 频道内搜索
  const [isLoadingSources, setIsLoadingSources] = useState(true);
  const [isLoadingVideos, setIsLoadingVideos] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [showBackToTop, setShowBackToTop] = useState(false);
  const [restoreChecked, setRestoreChecked] = useState(false);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const snapshotRef = useRef<HanimeSnapshot | null>(null);
  const pendingScrollTopRef = useRef<number | null>(null);
  const skipCategoryFetchRef = useRef(false);
  const skipVideoFetchRef = useRef(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  // 恢复快照
  useIsomorphicLayoutEffect(() => {
    const snapshot = consumeSnapshot();
    if (snapshot) {
      skipCategoryFetchRef.current = true;
      skipVideoFetchRef.current = true;
      pendingScrollTopRef.current = snapshot.scrollTop;
      setSources(snapshot.sources);
      setSelectedSource(snapshot.selectedSource);
      setCategories(snapshot.categories);
      setSelectedCategory(snapshot.selectedCategory);
      setVideos(snapshot.videos);
      setCurrentPage(snapshot.currentPage);
      setHasMore(snapshot.hasMore);
      setKeyword(snapshot.keyword || '');
      setSearching(!!snapshot.keyword);
    }
    setRestoreChecked(true);
  }, []);

  useIsomorphicLayoutEffect(() => {
    const target = pendingScrollTopRef.current;
    if (target == null || videos.length === 0) return;
    pendingScrollTopRef.current = null;
    scrollPageTo(target);
    const rafId = requestAnimationFrame(() => scrollPageTo(target));
    return () => cancelAnimationFrame(rafId);
  }, [videos]);

  useEffect(() => {
    snapshotRef.current = {
      sources, selectedSource, categories, selectedCategory,
      videos, currentPage, hasMore, scrollTop: 0, keyword,
    };
  }, [sources, selectedSource, categories, selectedCategory, videos, currentPage, hasMore, keyword]);

  const saveSnapshot = useCallback(() => {
    const snapshot = snapshotRef.current;
    if (!snapshot || snapshot.videos.length === 0) return;
    try {
      sessionStorage.setItem(HANIME_STATE_KEY, JSON.stringify({ ...snapshot, scrollTop: getPageScrollTop() }));
    } catch { /* ignore */ }
  }, []);

  // 源列表
  useEffect(() => {
    if (!restoreChecked) return;
    const fetchSources = async () => {
      setIsLoadingSources(true);
      try {
        const res = await fetch('/api/hanime/sources');
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data)) {
          const list = data.data as HanimeSource[];
          setSources(list);
          if (list.length > 0) {
            setSelectedSource((prev) => (prev && list.some((s) => s.key === prev) ? prev : list[0].key));
          }
        }
      } catch (e) {
        console.error('Failed to load hanime sources:', e);
      } finally {
        setIsLoadingSources(false);
      }
    };
    fetchSources();
  }, [restoreChecked]);

  const handleSourceChange = (key: string) => {
    setSelectedSource(key);
    setCategories([]);
    setSelectedCategory('');
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
    setKeyword('');
    setSearching(false);
  };

  // 分类
  useEffect(() => {
    if (!restoreChecked || !selectedSource) return;
    if (skipCategoryFetchRef.current) {
      skipCategoryFetchRef.current = false;
      return;
    }
    const fetchCategories = async () => {
      try {
        const res = await fetch(`/api/hanime/categories?source=${encodeURIComponent(selectedSource)}`);
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data) && data.data.length > 0) {
          const list = data.data as HanimeCategory[];
          setCategories(list);
          setSelectedCategory((prev) => (prev && list.some((c) => c.id === prev) ? prev : list[0].id));
        }
      } catch (e) {
        console.error('Failed to load hanime categories:', e);
      }
    };
    fetchCategories();
  }, [restoreChecked, selectedSource]);

  const handleCategoryChange = (value: string) => {
    setSelectedCategory(value);
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
    setKeyword('');
    setSearching(false);
  };

  // 列表 / 搜索
  useEffect(() => {
    if (!restoreChecked || !selectedSource) return;
    if (!searching && !selectedCategory) return;
    if (skipVideoFetchRef.current) {
      skipVideoFetchRef.current = false;
      return;
    }
    const fetchVideos = async () => {
      setIsLoadingVideos(true);
      try {
        const url = searching
          ? `/api/hanime/search?source=${encodeURIComponent(selectedSource)}&keyword=${encodeURIComponent(keyword)}&page=${currentPage}`
          : `/api/hanime/videos?source=${encodeURIComponent(selectedSource)}&categoryId=${encodeURIComponent(selectedCategory)}&page=${currentPage}`;
        const res = await fetch(url);
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data)) {
          setVideos((prev) => (currentPage === 1 ? data.data : [...prev, ...data.data]));
          setHasMore(data.page < data.pageCount);
        }
      } catch (e) {
        console.error('Failed to load hanime videos:', e);
      } finally {
        setIsLoadingVideos(false);
      }
    };
    fetchVideos();
  }, [restoreChecked, selectedSource, selectedCategory, currentPage, searching]);

  // 搜索提交后 currentPage 已置 1 但 searching 翻转时上面 effect 可能用旧 keyword，补一次
  const doSearch = useCallback(() => {
    const kw = searchInputRef.current?.value.trim() ?? '';
    setKeyword(kw);
    setSearching(kw.length > 0);
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
  }, []);

  const clearSearch = useCallback(() => {
    if (searchInputRef.current) searchInputRef.current.value = '';
    setKeyword('');
    setSearching(false);
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
  }, []);

  const hasVideos = videos.length > 0;
  useEffect(() => {
    if (!hasVideos || !loadMoreRef.current) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !isLoadingVideos) {
          setCurrentPage((prev) => prev + 1);
        }
      },
      { rootMargin: '240px 0px', threshold: 0.1 }
    );
    observer.observe(loadMoreRef.current);
    return () => observer.disconnect();
  }, [hasVideos, hasMore, isLoadingVideos]);

  useEffect(() => {
    const handleScroll = () => setShowBackToTop(getPageScrollTop() > 300);
    handleScroll();
    document.body.addEventListener('scroll', handleScroll, { passive: true });
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => {
      document.body.removeEventListener('scroll', handleScroll);
      window.removeEventListener('scroll', handleScroll);
    };
  }, []);

  const scrollToTop = () => {
    try {
      document.body.scrollTo({ top: 0, behavior: 'smooth' });
      document.documentElement.scrollTo({ top: 0, behavior: 'smooth' });
    } catch {
      scrollPageTo(0);
    }
  };

  return (
    <PageLayout activePath='/hanime'>
      <div className='px-4 sm:px-10 py-4 sm:py-8 overflow-visible mb-10'>
        <div className='mb-6 flex items-start justify-between gap-4'>
          <div>
            <h1 className='text-2xl font-bold text-gray-800 dark:text-gray-200'>里番</h1>
            <p className='text-sm text-gray-500 dark:text-gray-400 mt-1'>hanime1 自建源 · {categories.length > 0 ? `${categories.length} 个分类` : ''} · 内容来自第三方</p>
          </div>
          <Link
            href='/'
            className='inline-flex items-center gap-1 rounded-lg px-3 py-2 text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100'
          >
            <ArrowLeft className='h-4 w-4' />
            返回首页
          </Link>
        </div>

        {/* 源（通常只有一个 hanime1，有多个才显示） */}
        <div className='max-w-4xl mx-auto mb-6'>
          {isLoadingSources ? (
            <div className='flex items-center justify-center h-12 bg-gray-50/80 rounded-lg border border-gray-200/50 dark:bg-gray-800 dark:border-gray-700'>
              <Loader2 className='h-5 w-5 animate-spin text-gray-400' />
              <span className='ml-2 text-sm text-gray-500 dark:text-gray-400'>加载采集源中...</span>
            </div>
          ) : sources.length === 0 ? (
            <div className='rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300'>
              未找到 hanime 采集源。请先去后台「源管理 → 添加自定义源」加
              <code className='mx-1 rounded bg-red-100 px-1 dark:bg-red-900'>key: hanime1, api: http://hanime1-maccms:3001/api.php/provide/vod</code>
              ，再点「清除缓存」/ 重启 moontv-core。
            </div>
          ) : sources.length > 1 ? (
            <div>
              <div className='text-xs text-gray-500 dark:text-gray-400 mb-2 px-4'>服务</div>
              <div className='flex gap-2 px-4 overflow-x-auto'>
                {sources.map((s) => (
                  <button
                    key={s.key}
                    onClick={() => handleSourceChange(s.key)}
                    className={`px-4 py-2 rounded-lg text-sm font-medium whitespace-nowrap flex-shrink-0 ${selectedSource === s.key ? 'bg-blue-600 text-white' : 'bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700'}`}
                  >
                    {s.name}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
        </div>

        {/* 频道内搜索 */}
        {sources.length > 0 && (
          <div className='max-w-4xl mx-auto mb-6'>
            <div className='flex gap-2 px-4'>
              <div className='relative flex-1'>
                <Search className='absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400' />
                <input
                  ref={searchInputRef}
                  defaultValue={keyword}
                  placeholder='在里番频道内搜索…'
                  className='w-full rounded-lg border border-gray-200 bg-white/80 py-2 pl-9 pr-3 text-sm outline-none focus:border-blue-500 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200'
                  onKeyDown={(e) => { if (e.key === 'Enter') doSearch(); }}
                />
              </div>
              <button onClick={doSearch} className='rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700'>搜索</button>
              {searching && (
                <button onClick={clearSearch} className='rounded-lg bg-gray-100 px-4 py-2 text-sm text-gray-700 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300'>清除</button>
              )}
            </div>
          </div>
        )}

        {/* 分类（面包屑：点一下展开分组） */}
        {selectedSource && !searching && categories.length > 1 && (
          <div className='max-w-4xl mx-auto mb-8'>
            <div className='text-xs text-gray-500 dark:text-gray-400 mb-2 px-4'>分类</div>
            <CategoryBreadcrumb
              groups={buildCrumbGroups(categories)}
              selectedId={selectedCategory}
              onChange={handleCategoryChange}
            />
          </div>
        )}

        {selectedSource && (
          <div className='max-w-[95%] mx-auto mt-8'>
            <div className='mb-4'>
              <h2 className='text-xl font-bold text-gray-800 dark:text-gray-200'>
                {searching ? `搜索：${keyword}` : categories.find((c) => c.id === selectedCategory)?.name || '里番列表'}
              </h2>
            </div>
            {isLoadingVideos && currentPage === 1 ? (
              <div className='flex justify-center items-center h-40'>
                <div className='animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500'></div>
              </div>
            ) : videos.length === 0 ? (
              <div className='text-center text-gray-500 py-8 dark:text-gray-400'>暂无内容</div>
            ) : (
              <>
                <div className='video-grid px-0 sm:px-2'>
                  {videos.map((item) => (
                    <div key={`${item.source}-${item.id}`} className='w-full'>
                      <VideoCard
                        id={item.id}
                        title={item.title}
                        poster={item.poster}
                        episodes={item.episodes.length}
                        source={item.source}
                        source_name={item.source_name}
                        douban_id={item.douban_id}
                        year={item.year}
                        from='source-search'
                        type='tv'
                        cmsData={{ desc: item.desc, episodes: item.episodes, episodes_titles: item.episodes_titles }}
                        onBeforeNavigate={saveSnapshot}
                      />
                    </div>
                  ))}
                </div>
                <div ref={loadMoreRef} className='flex justify-center items-center py-8'>
                  {isLoadingVideos && <div className='animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500'></div>}
                  {!hasMore && videos.length > 0 && <span className='text-sm text-gray-500 dark:text-gray-400'>没有更多了</span>}
                </div>
              </>
            )}
          </div>
        )}
      </div>

      <button
        onClick={scrollToTop}
        className={`fixed bottom-20 md:bottom-6 right-6 z-[500] w-12 h-12 bg-green-500/90 hover:bg-green-500 text-white rounded-full shadow-lg backdrop-blur-sm transition-all duration-300 ease-in-out flex items-center justify-center group ${showBackToTop ? 'opacity-100 translate-y-0 pointer-events-auto' : 'opacity-0 translate-y-4 pointer-events-none'}`}
        aria-label='返回顶部'
      >
        <ChevronUp className='w-6 h-6 transition-transform group-hover:scale-110' />
      </button>
    </PageLayout>
  );
}

export default function HanimePage() {
  return (
    <Suspense>
      <HanimePageClient />
    </Suspense>
  );
}
