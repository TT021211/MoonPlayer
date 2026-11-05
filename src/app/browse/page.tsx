/* eslint-disable @typescript-eslint/no-explicit-any, react-hooks/exhaustive-deps */
'use client';

import { ArrowLeft, ChevronUp, Loader2 } from 'lucide-react';
import Link from 'next/link';
import { Suspense, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { isAnimeCategoryText } from '@/lib/anime-keyword-expr';
import { SearchResult } from '@/lib/types';

import CapsuleSwitch from '@/components/CapsuleSwitch';
import PageLayout from '@/components/PageLayout';
import VideoCard from '@/components/VideoCard';

interface BrowseSource {
  key: string;
  name: string;
  api: string;
}

interface BrowseCategory {
  id: string;
  name: string;
  pid: string;
}

interface BrowseSnapshot {
  sources: BrowseSource[];
  selectedSource: string;
  categories: BrowseCategory[];
  selectedCategory: string;
  videos: SearchResult[];
  currentPage: number;
  hasMore: boolean;
  scrollTop: number;
}

const BROWSE_STATE_KEY = 'browse_state';

const getPageScrollTop = () =>
  document.body.scrollTop || document.documentElement.scrollTop || 0;

const scrollPageTo = (top: number) => {
  document.body.scrollTop = top;
  document.documentElement.scrollTop = top;
};

const useIsomorphicLayoutEffect =
  typeof window === 'undefined' ? useEffect : useLayoutEffect;

const consumeSnapshot = (): BrowseSnapshot | null => {
  if (typeof window === 'undefined') return null;
  try {
    const raw = sessionStorage.getItem(BROWSE_STATE_KEY);
    sessionStorage.removeItem(BROWSE_STATE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as BrowseSnapshot;
    if (
      !parsed?.selectedSource ||
      !Array.isArray(parsed.videos) ||
      parsed.videos.length === 0
    )
      return null;
    return parsed;
  } catch {
    return null;
  }
};

function BrowsePageClient({ initialSource }: { initialSource: string }) {
  const [sources, setSources] = useState<BrowseSource[]>([]);
  const [selectedSource, setSelectedSource] = useState(initialSource);
  const [categories, setCategories] = useState<BrowseCategory[]>([]);
  const [selectedCategory, setSelectedCategory] = useState('');
  const [videos, setVideos] = useState<SearchResult[]>([]);
  const [isLoadingSources, setIsLoadingSources] = useState(true);
  const [isLoadingVideos, setIsLoadingVideos] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [showBackToTop, setShowBackToTop] = useState(false);
  const [restoreChecked, setRestoreChecked] = useState(false);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const snapshotRef = useRef<BrowseSnapshot | null>(null);
  const pendingScrollTopRef = useRef<number | null>(null);
  const skipCategoryFetchRef = useRef(false);
  const skipVideoFetchRef = useRef(false);
  const seenIdsRef = useRef<Set<string>>(new Set());

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
      seenIdsRef.current = new Set(
        snapshot.videos.map((v) => `${v.source}-${v.id}`)
      );
      setCurrentPage(snapshot.currentPage);
      setHasMore(snapshot.hasMore);
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
      sources,
      selectedSource,
      categories,
      selectedCategory,
      videos,
      currentPage,
      hasMore,
      scrollTop: 0,
    };
  }, [
    sources,
    selectedSource,
    categories,
    selectedCategory,
    videos,
    currentPage,
    hasMore,
  ]);

  const saveSnapshot = () => {
    const snapshot = snapshotRef.current;
    if (!snapshot || snapshot.videos.length === 0) return;
    try {
      sessionStorage.setItem(
        BROWSE_STATE_KEY,
        JSON.stringify({ ...snapshot, scrollTop: getPageScrollTop() })
      );
    } catch {
      /* ignore */
    }
  };

  // 源列表
  useEffect(() => {
    if (!restoreChecked) return;
    const fetchSources = async () => {
      setIsLoadingSources(true);
      try {
        const res = await fetch('/api/source-search/sources');
        const data = await res.json();
        if (Array.isArray(data.sources)) {
          const list = data.sources as BrowseSource[];
          setSources(list);
          setSelectedSource((prev) => {
            if (prev && list.some((s) => s.key === prev)) return prev;
            return list.length > 0 ? list[0].key : '';
          });
        }
      } catch (e) {
        console.error('Failed to load browse sources:', e);
      } finally {
        setIsLoadingSources(false);
      }
    };
    fetchSources();
  }, [restoreChecked]);

  const resetList = () => {
    setCurrentPage(1);
    setVideos([]);
    seenIdsRef.current = new Set();
    setHasMore(true);
  };

  const handleSourceChange = (key: string) => {
    setSelectedSource(key);
    setCategories([]);
    setSelectedCategory('');
    resetList();
  };

  // 分类（取自站点真实 ?ac=list，非写死）
  useEffect(() => {
    if (!restoreChecked || !selectedSource) return;
    if (skipCategoryFetchRef.current) {
      skipCategoryFetchRef.current = false;
      return;
    }
    const fetchCategories = async () => {
      try {
        const res = await fetch(
          `/api/source-search/categories?source=${encodeURIComponent(selectedSource)}`
        );
        const data = await res.json();
        if (Array.isArray(data.categories) && data.categories.length > 0) {
          const list = data.categories as BrowseCategory[];
          setCategories(list);
          setSelectedCategory((prev) =>
            prev && list.some((c) => c.id === prev) ? prev : list[0].id
          );
        } else {
          setCategories([]);
          setSelectedCategory('');
        }
      } catch (e) {
        console.error('Failed to load browse categories:', e);
      }
    };
    fetchCategories();
  }, [restoreChecked, selectedSource]);

  const handleCategoryChange = (value: string) => {
    if (value === selectedCategory) return;
    setSelectedCategory(value);
    resetList();
  };

  // 列表（去重收敛：上游 pagecount 缺失或卡死时靠“无新 id”停）
  useEffect(() => {
    if (!restoreChecked || !selectedSource) return;
    if (!selectedCategory) return;
    if (skipVideoFetchRef.current) {
      skipVideoFetchRef.current = false;
      return;
    }
    const fetchVideos = async () => {
      setIsLoadingVideos(true);
      try {
        const res = await fetch(
          `/api/source-search/videos?source=${encodeURIComponent(selectedSource)}&categoryId=${encodeURIComponent(selectedCategory)}&page=${currentPage}`
        );
        const data = await res.json();
        if (Array.isArray(data.results)) {
          const incoming = (data.results as SearchResult[]).filter((item) => {
            const key = `${item.source}-${item.id}`;
            if (seenIdsRef.current.has(key)) return false;
            seenIdsRef.current.add(key);
            return true;
          });
          setVideos((prev) =>
            currentPage === 1 ? incoming : [...prev, ...incoming]
          );
          const pageCount = Number(data.pageCount) || 0;
          const page = Number(data.page) || currentPage;
          setHasMore(
            incoming.length > 0 && (pageCount <= 0 || page < pageCount)
          );
        }
      } catch (e) {
        console.error('Failed to load browse videos:', e);
      } finally {
        setIsLoadingVideos(false);
      }
    };
    fetchVideos();
  }, [restoreChecked, selectedSource, selectedCategory, currentPage]);

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

  // 父 / 子两级（pid=0 为父；无 pid 体系时单行展示）
  const parentCats = categories.filter(
    (c) => c.pid === '0' || !categories.some((x) => x.id === c.pid)
  );
  const topCats = parentCats.length > 0 ? parentCats : categories;
  const selCat = categories.find((c) => c.id === selectedCategory);
  const activeParent =
    selCat && selCat.pid !== '0' && topCats.some((c) => c.id === selCat.pid)
      ? selCat.pid
      : topCats.some((c) => c.id === selectedCategory)
        ? selectedCategory
        : (topCats[0]?.id ?? '');
  const childCats = categories.filter(
    (c) => c.pid !== '0' && c.pid === activeParent
  );
  const activeSource = sources.find((s) => s.key === selectedSource);
  const activeCatName =
    categories.find((c) => c.id === selectedCategory)?.name || '';

  const handleParentChange = (value: string) => {
    const kids = categories.filter((c) => c.pid !== '0' && c.pid === value);
    handleCategoryChange(kids.length > 0 ? kids[0].id : value);
  };

  return (
    <PageLayout activePath='/browse'>
      <div className='px-4 sm:px-10 py-4 sm:py-8 overflow-visible mb-10'>
        <div className='mb-6 flex items-start justify-between gap-4'>
          <div>
            <h1 className='text-2xl font-bold text-gray-800 dark:text-gray-200'>
              源站浏览{activeSource ? ` · ${activeSource.name}` : ''}
            </h1>
            <p className='text-sm text-gray-500 dark:text-gray-400 mt-1'>
              分类取自各源真实站点（?ac=list 同步）
            </p>
          </div>
          <Link
            href='/'
            className='inline-flex items-center gap-1 rounded-lg px-3 py-2 text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100'
          >
            <ArrowLeft className='h-4 w-4' />
            返回首页
          </Link>
        </div>

        <div className='max-w-4xl mx-auto mb-6'>
          {isLoadingSources ? (
            <div className='flex items-center justify-center h-12 bg-gray-50/80 rounded-lg border border-gray-200/50 dark:bg-gray-800 dark:border-gray-700'>
              <Loader2 className='h-5 w-5 animate-spin text-gray-400' />
              <span className='ml-2 text-sm text-gray-500 dark:text-gray-400'>
                加载采集源中...
              </span>
            </div>
          ) : sources.length === 0 ? (
            <div className='rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300'>
              没有可用的采集源，请先去后台「源管理」添加自定义源。
            </div>
          ) : (
            sources.length > 1 && (
              <div>
                <div className='text-xs text-gray-500 dark:text-gray-400 mb-2 px-4'>
                  服务
                </div>
                <div className='flex px-4'>
                  <CapsuleSwitch
                    options={sources.map((s) => ({
                      label: s.name,
                      value: s.key,
                    }))}
                    active={selectedSource}
                    onChange={handleSourceChange}
                  />
                </div>
              </div>
            )
          )}
        </div>

        {selectedSource && categories.length > 0 && (
          <div className='max-w-4xl mx-auto mb-8 space-y-3'>
            <div>
              <div className='text-xs text-gray-500 dark:text-gray-400 mb-2 px-4'>
                分类
              </div>
              <div className='flex px-4'>
                <CapsuleSwitch
                  options={topCats.map((c) => ({
                    label: c.name,
                    value: c.id,
                  }))}
                  active={activeParent}
                  onChange={handleParentChange}
                />
              </div>
            </div>
            {childCats.length > 0 && (
              <div>
                <div className='flex px-4'>
                  <CapsuleSwitch
                    options={childCats.map((c) => ({
                      label: c.name,
                      value: c.id,
                    }))}
                    active={selectedCategory}
                    onChange={handleCategoryChange}
                  />
                </div>
              </div>
            )}
          </div>
        )}

        {selectedSource && (
          <div className='max-w-[95%] mx-auto mt-8'>
            <div className='mb-4'>
              <h2 className='text-xl font-bold text-gray-800 dark:text-gray-200'>
                {activeCatName || '源站列表'}
              </h2>
            </div>
            {isLoadingVideos && currentPage === 1 ? (
              <div className='flex justify-center items-center h-40'>
                <div className='animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500'></div>
              </div>
            ) : videos.length === 0 ? (
              <div className='text-center text-gray-500 py-8 dark:text-gray-400'>
                暂无内容
              </div>
            ) : (
              <>
                <div className='grid grid-cols-3 gap-x-2 gap-y-14 sm:gap-y-20 px-0 sm:px-2 sm:grid-cols-[repeat(auto-fill,_minmax(11rem,_1fr))] sm:gap-x-8'>
                  {videos.map((item) => (
                    <div
                      key={`${item.source}-${item.id}`}
                      className='w-full'
                    >
                      <VideoCard
                        id={item.id}
                        title={item.title}
                        poster={item.poster}
                        episodes={item.episodes?.length ?? 0}
                        source={item.source}
                        source_name={item.source_name}
                        douban_id={item.douban_id}
                        year={item.year}
                        from='source-search'
                        type={
                          (item.episodes?.length ?? 0) > 1 ? 'tv' : 'movie'
                        }
                        isAnime={isAnimeCategoryText(
                          item.type_name,
                          item.class
                        )}
                        onBeforeNavigate={saveSnapshot}
                      />
                    </div>
                  ))}
                </div>
                <div
                  ref={loadMoreRef}
                  className='flex justify-center items-center py-8'
                >
                  {isLoadingVideos && (
                    <div className='animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500'></div>
                  )}
                  {!hasMore && videos.length > 0 && (
                    <span className='text-sm text-gray-500 dark:text-gray-400'>
                      没有更多了
                    </span>
                  )}
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

export default function BrowsePage({
  searchParams,
}: {
  searchParams?: { source?: string };
}) {
  return (
    <Suspense>
      <BrowsePageClient initialSource={searchParams?.source || ''} />
    </Suspense>
  );
}
