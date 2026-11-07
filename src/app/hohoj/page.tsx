/* eslint-disable @typescript-eslint/no-explicit-any, react-hooks/exhaustive-deps */
'use client';

import { ArrowLeft, ChevronUp, Loader2, Search } from 'lucide-react';
import Link from 'next/link';
import { Suspense, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';

import { HOHOJ_STATE_KEY } from '@/lib/hohoj.client';
import { SearchResult } from '@/lib/types';

import CapsuleSwitch from '@/components/CapsuleSwitch';
import CategoryBreadcrumb, {
  buildCrumbGroups,
} from '@/components/CategoryBreadcrumb';
import PageLayout from '@/components/PageLayout';
import VideoCard from '@/components/VideoCard';

interface HohojModel {
  id: string;
  name: string;
  pic: string;
}

interface HohojSource {
  key: string;
  name: string;
  api: string;
}

interface HohojCategory {
  id: string;
  name: string;
  pid: string;
  group?: string;
}

interface HohojSnapshot {
  sources: HohojSource[];
  selectedSource: string;
  categories: HohojCategory[];
  selectedCategory: string;
  selectedModel: { mid: string; name: string } | null;
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

const consumeSnapshot = (): HohojSnapshot | null => {
  if (typeof window === 'undefined') return null;
  try {
    const raw = sessionStorage.getItem(HOHOJ_STATE_KEY);
    sessionStorage.removeItem(HOHOJ_STATE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as HohojSnapshot;
    if (!parsed?.selectedSource || !Array.isArray(parsed.videos) || parsed.videos.length === 0) return null;
    return parsed;
  } catch {
    return null;
  }
};

function HohojPageClient() {
  const [sources, setSources] = useState<HohojSource[]>([]);
  const [selectedSource, setSelectedSource] = useState('');
  const [categories, setCategories] = useState<HohojCategory[]>([]);
  const [selectedCategory, setSelectedCategory] = useState('');
  const [videos, setVideos] = useState<SearchResult[]>([]);
  const [keyword, setKeyword] = useState('');
  const [searching, setSearching] = useState(false); // 空 = 浏览模式，非空 = 频道内搜索
  const [isLoadingSources, setIsLoadingSources] = useState(true);
  const [isLoadingVideos, setIsLoadingVideos] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  // 人物墙
  const [view, setView] = useState<'videos' | 'models'>('videos');
  const [modelOrder, setModelOrder] = useState<'popular' | 'views'>('popular');
  const [models, setModels] = useState<HohojModel[]>([]);
  const [modelPage, setModelPage] = useState(1);
  const [modelsHasMore, setModelsHasMore] = useState(true);
  const [isLoadingModels, setIsLoadingModels] = useState(false);
  const [selectedModel, setSelectedModel] = useState<{ mid: string; name: string } | null>(null);
  const modelMoreRef = useRef<HTMLDivElement>(null);
  const seenModelIdsRef = useRef<Set<string>>(new Set());
  const [showBackToTop, setShowBackToTop] = useState(false);
  const [restoreChecked, setRestoreChecked] = useState(false);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const snapshotRef = useRef<HohojSnapshot | null>(null);
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
      setSelectedModel(snapshot.selectedModel || null);
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
      selectedModel, videos, currentPage, hasMore, scrollTop: 0, keyword,
    };
  }, [sources, selectedSource, categories, selectedCategory, selectedModel, videos, currentPage, hasMore, keyword]);

  const saveSnapshot = useCallback(() => {
    const snapshot = snapshotRef.current;
    if (!snapshot || snapshot.videos.length === 0) return;
    try {
      sessionStorage.setItem(HOHOJ_STATE_KEY, JSON.stringify({ ...snapshot, scrollTop: getPageScrollTop() }));
    } catch { /* ignore */ }
  }, []);

  // 源列表
  useEffect(() => {
    if (!restoreChecked) return;
    const fetchSources = async () => {
      setIsLoadingSources(true);
      try {
        const res = await fetch('/api/hohoj/sources');
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data)) {
          const list = data.data as HohojSource[];
          setSources(list);
          if (list.length > 0) {
            setSelectedSource((prev) => (prev && list.some((s) => s.key === prev) ? prev : list[0].key));
          }
        }
      } catch (e) {
        console.error('Failed to load hohoj sources:', e);
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
    setSelectedModel(null);
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
        const res = await fetch(`/api/hohoj/categories?source=${encodeURIComponent(selectedSource)}`);
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data) && data.data.length > 0) {
          const list = data.data as HohojCategory[];
          setCategories(list);
          setSelectedCategory((prev) => (prev && list.some((c) => c.id === prev) ? prev : list[0].id));
        }
      } catch (e) {
        console.error('Failed to load hohoj categories:', e);
      }
    };
    fetchCategories();
  }, [restoreChecked, selectedSource]);

  const handleCategoryChange = (value: string) => {
    if (value === selectedCategory) return;
    setSelectedCategory(value);
    setSelectedModel(null);
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
          ? `/api/hohoj/search?source=${encodeURIComponent(selectedSource)}&keyword=${encodeURIComponent(keyword)}&page=${currentPage}`
          : `/api/hohoj/videos?source=${encodeURIComponent(selectedSource)}&categoryId=${encodeURIComponent(selectedCategory)}&page=${currentPage}`;
        const res = await fetch(url);
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data)) {
          setVideos((prev) => (currentPage === 1 ? data.data : [...prev, ...data.data]));
          setHasMore(data.page < data.pageCount);
        }
      } catch (e) {
        console.error('Failed to load hohoj videos:', e);
      } finally {
        setIsLoadingVideos(false);
      }
    };
    fetchVideos();
  }, [restoreChecked, selectedSource, selectedCategory, currentPage, searching]);

  // 人物墙列表
  useEffect(() => {
    if (!restoreChecked || !selectedSource || view !== 'models') return;
    const fetchModels = async () => {
      setIsLoadingModels(true);
      try {
        const res = await fetch(`/api/hohoj/models?source=${encodeURIComponent(selectedSource)}&order=${modelOrder}&page=${modelPage}`);
        const data = await res.json();
        if (data.code === 200 && Array.isArray(data.data)) {
          const incoming = (data.data as HohojModel[]).filter((m) => {
            if (seenModelIdsRef.current.has(m.id)) return false;
            seenModelIdsRef.current.add(m.id);
            return true;
          });
          setModels((prev) => (modelPage === 1 ? incoming : [...prev, ...incoming]));
          const pageCount = Number(data.pageCount) || 0;
          const page = Number(data.page) || modelPage;
          setModelsHasMore(incoming.length > 0 && (pageCount <= 0 || page < pageCount));
        }
      } catch (e) {
        console.error('Failed to load hohoj models:', e);
      } finally {
        setIsLoadingModels(false);
      }
    };
    fetchModels();
  }, [restoreChecked, selectedSource, view, modelOrder, modelPage]);

  useEffect(() => {
    if (models.length === 0 || !modelMoreRef.current) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && modelsHasMore && !isLoadingModels) {
          setModelPage((prev) => prev + 1);
        }
      },
      { rootMargin: '240px 0px', threshold: 0.1 }
    );
    observer.observe(modelMoreRef.current);
    return () => observer.disconnect();
  }, [models.length, modelsHasMore, isLoadingModels]);

  const handleViewChange = (value: string) => {
    if (value === 'models') {
      setView('models');
      return;
    }
    // 切回影片：若正看着人物作品，回到分类浏览
    setView('videos');
    if (selectedModel) {
      setSelectedModel(null);
      setSelectedCategory(categories[0]?.id || '');
      setCurrentPage(1);
      setVideos([]);
      setHasMore(true);
      setKeyword('');
      setSearching(false);
    }
  };

  const handleModelOrderChange = (value: string) => {
    setModelOrder(value === 'views' ? 'views' : 'popular');
    setModelPage(1);
    setModels([]);
    seenModelIdsRef.current = new Set();
    setModelsHasMore(true);
  };

  const handleModelSelect = (mid: string, name: string) => {
    setSelectedModel({ mid, name });
    setSelectedCategory(`model-${mid}`);
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
    setKeyword('');
    setSearching(false);
    setView('videos');
    scrollPageTo(0);
  };

  const backToModelWall = () => {
    setSelectedModel(null);
    setView('models');
    scrollPageTo(0);
  };

  // 搜索提交后 currentPage 已置 1 但 searching 翻转时上面 effect 可能用旧 keyword，补一次
  const doSearch = useCallback(() => {
    const kw = searchInputRef.current?.value.trim() ?? '';
    setKeyword(kw);
    setSearching(kw.length > 0);
    setSelectedModel(null);
    setView('videos');
    setCurrentPage(1);
    setVideos([]);
    setHasMore(true);
  }, []);

  const clearSearch = useCallback(() => {
    if (searchInputRef.current) searchInputRef.current.value = '';
    setKeyword('');
    setSearching(false);
    setSelectedModel(null);
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
    <PageLayout activePath='/hohoj'>
      <div className='px-4 sm:px-10 py-4 sm:py-8 overflow-visible mb-10'>
        <div className='mb-6 flex items-start justify-between gap-4'>
          <div>
            <h1 className='text-2xl font-bold text-gray-800 dark:text-gray-200'>HoHo剧场</h1>
            <p className='text-sm text-gray-500 dark:text-gray-400 mt-1'>hohoj 自建源 · {categories.length > 0 ? `${categories.length} 个分类` : ''} · 内容来自第三方</p>
          </div>
          <Link
            href='/'
            className='inline-flex items-center gap-1 rounded-lg px-3 py-2 text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-gray-100'
          >
            <ArrowLeft className='h-4 w-4' />
            返回首页
          </Link>
        </div>

        {/* 源（通常只有一个 hohoj，有多个才显示） */}
        <div className='max-w-4xl mx-auto mb-6'>
          {isLoadingSources ? (
            <div className='flex items-center justify-center h-12 bg-gray-50/80 rounded-lg border border-gray-200/50 dark:bg-gray-800 dark:border-gray-700'>
              <Loader2 className='h-5 w-5 animate-spin text-gray-400' />
              <span className='ml-2 text-sm text-gray-500 dark:text-gray-400'>加载采集源中...</span>
            </div>
          ) : sources.length === 0 ? (
            <div className='rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300'>
              未找到 hohoj 采集源。请先去后台「源管理 → 添加自定义源」加
              <code className='mx-1 rounded bg-red-100 px-1 dark:bg-red-900'>key: hohoj, api: http://maccms-hub:3001/hohoj/api.php/provide/vod</code>
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
                  placeholder='在HoHo剧场频道内搜索…'
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

        {/* 影片 / 人物切换 */}
        {selectedSource && (
          <div className='flex justify-center mt-2 mb-6'>
            <CapsuleSwitch
              options={[
                { label: '影片', value: 'videos' },
                { label: '女优', value: 'models' },
              ]}
              active={view}
              onChange={handleViewChange}
            />
          </div>
        )}

        {/* 分类（面包屑：点一下展开分组） */}
        {selectedSource && view === 'videos' && !searching && !selectedModel && categories.length > 1 && (
          <div className='max-w-4xl mx-auto mb-8'>
            <div className='text-xs text-gray-500 dark:text-gray-400 mb-2 px-4'>分类</div>
            <CategoryBreadcrumb
              groups={buildCrumbGroups(categories)}
              selectedId={selectedCategory}
              onChange={handleCategoryChange}
            />
          </div>
        )}

        {/* 人物墙 */}
        {selectedSource && view === 'models' && (
          <div className='max-w-[95%] mx-auto mt-8'>
            <div className='flex px-4 mb-6'>
              <CapsuleSwitch
                options={[
                  { label: '最熱門', value: 'popular' },
                  { label: '最多觀看', value: 'views' },
                ]}
                active={modelOrder}
                onChange={handleModelOrderChange}
              />
            </div>
            {isLoadingModels && modelPage === 1 ? (
              <div className='flex justify-center items-center h-40'>
                <div className='animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500'></div>
              </div>
            ) : models.length === 0 ? (
              <div className='text-center text-gray-500 py-8 dark:text-gray-400'>暂无内容</div>
            ) : (
              <>
                <div className='grid grid-cols-3 gap-x-2 gap-y-6 px-0 sm:px-2 sm:grid-cols-[repeat(auto-fill,_minmax(9rem,_1fr))] sm:gap-x-8'>
                  {models.map((m) => (
                    <button
                      key={m.id}
                      type='button'
                      onClick={() => handleModelSelect(m.id, m.name)}
                      className='flex flex-col items-center gap-2 group cursor-pointer'
                    >
                      <img
                        src={
                          m.pic && /^https?:\/\//i.test(m.pic) && !m.pic.startsWith('/api/')
                            ? `/api/image-proxy?url=${encodeURIComponent(m.pic)}`
                            : m.pic || '/logo.png'
                        }
                        alt={m.name}
                        loading='lazy'
                        onError={(e) => {
                          e.currentTarget.src = '/logo.png';
                        }}
                        className='w-20 h-20 sm:w-24 sm:h-24 rounded-full object-cover bg-gray-100 dark:bg-gray-800 transition-transform group-hover:scale-105'
                      />
                      <span className='text-xs sm:text-sm text-gray-700 dark:text-gray-300 truncate max-w-full group-hover:text-red-600 dark:group-hover:text-red-400'>
                        {m.name}
                      </span>
                    </button>
                  ))}
                </div>
                <div ref={modelMoreRef} className='flex justify-center items-center py-8'>
                  {isLoadingModels && <div className='animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500'></div>}
                  {!modelsHasMore && models.length > 0 && <span className='text-sm text-gray-500 dark:text-gray-400'>没有更多了</span>}
                </div>
              </>
            )}
          </div>
        )}

        {selectedSource && view === 'videos' && (
          <div className='max-w-[95%] mx-auto mt-8'>
            <div className='mb-4 flex items-center gap-3'>
              <h2 className='text-xl font-bold text-gray-800 dark:text-gray-200'>
                {searching ? `搜索：${keyword}` : selectedModel ? selectedModel.name : categories.find((c) => c.id === selectedCategory)?.name || 'HoHo剧场列表'}
              </h2>
              {selectedModel && !searching && (
                <button
                  type='button'
                  onClick={backToModelWall}
                  className='rounded-lg px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-300 dark:hover:bg-gray-800'
                >
                  ← 返回女优墙
                </button>
              )}
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
                        posterAspect='aspect-[3/2]'
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

export default function HohojPage() {
  return (
    <Suspense>
      <HohojPageClient />
    </Suspense>
  );
}
