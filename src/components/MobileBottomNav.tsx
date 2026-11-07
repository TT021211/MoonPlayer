/* eslint-disable @typescript-eslint/no-explicit-any */

'use client';

import { Blend, Cat, Clover, Film, Flame, Globe, Heart, Home, MonitorPlay, SquarePlay, Star, Tv, Users } from 'lucide-react';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';

interface MobileBottomNavProps {
  /**
   * 主动指定当前激活的路径。当未提供时，自动使用 usePathname() 获取的路径。
   */
  activePath?: string;
}

const MobileBottomNav = ({ activePath }: MobileBottomNavProps) => {
  const pathname = usePathname();
  const searchParams = useSearchParams();

  // 直接使用当前路由状态，确保立即响应路由变化
  const getCurrentFullPath = () => {
    const queryString = searchParams.toString();
    return queryString ? `${pathname}?${queryString}` : pathname;
  };
  const currentActive = activePath ?? getCurrentFullPath();

  const [navItems, setNavItems] = useState([
    { icon: Home, label: '首页', href: '/' },
    {
      icon: Film,
      label: '电影',
      key: 'movie',
      href: '/douban?type=movie',
    },
    {
      icon: Tv,
      label: '剧集',
      key: 'tv',
      href: '/douban?type=tv',
    },
    {
      icon: Cat,
      label: '动漫',
      key: 'anime',
      href: '/douban?type=anime',
    },
    {
      icon: Flame,
      label: '里番',
      key: 'hanime',
      href: '/hanime',
    },
    {
      icon: Heart,
      label: '爱情岛',
      key: 'aqdlt',
      href: '/aqdlt',
    },
    {
      icon: SquarePlay,
      label: 'HoHoJ',
      key: 'hohoj',
      href: '/hohoj',
    },
    {
      icon: MonitorPlay,
      label: 'KinoStream',
      key: 'kinostream',
      href: '/kinostream',
    },
    {
      icon: Clover,
      label: '综艺',
      key: 'show',
      href: '/douban?type=show',
    },
  ]);

  useEffect(() => {
    const runtimeConfig = (window as any).RUNTIME_CONFIG;

    // 基础导航项（不包括观影室）
    const items = [
      { icon: Home, label: '首页', href: '/' },
      {
        icon: Film,
        label: '电影',
      key: 'movie',
        href: '/douban?type=movie',
      },
      {
        icon: Tv,
        label: '剧集',
      key: 'tv',
        href: '/douban?type=tv',
      },
      {
        icon: Cat,
        label: '动漫',
      key: 'anime',
        href: '/douban?type=anime',
      },
      {
        icon: Flame,
        label: '里番',
      key: 'hanime',
        href: '/hanime',
      },
      {
        icon: Heart,
        label: '爱情岛',
      key: 'aqdlt',
        href: '/aqdlt',
      },
      {
        icon: SquarePlay,
        label: 'HoHoJ',
      key: 'hohoj',
        href: '/hohoj',
      },
      {
        icon: MonitorPlay,
        label: 'KinoStream',
        key: 'kinostream',
        href: '/kinostream',
      },
      {
        icon: Clover,
        label: '综艺',
      key: 'show',
        href: '/douban?type=show',
      },
    ];

    // 已精简：网络直播/私人影库/高级推荐/观影室入口移除

    // 添加自定义分类（如果有）
    if (runtimeConfig?.CUSTOM_CATEGORIES?.length > 0) {
      items.push({
        icon: Star,
        label: '自定义',
        key: 'custom',
        href: '/douban?type=custom',
      });
    }

    // 特殊源入口不在导航展示，只能手动访问 /under

    setNavItems(items);
  }, []);

  const isActive = (href: string) => {
    const typeMatch = href.match(/type=([^&]+)/)?.[1];

    // 解码URL以进行正确的比较
    const decodedActive = decodeURIComponent(currentActive);
    const decodedItemHref = decodeURIComponent(href);

    return (
      decodedActive === decodedItemHref ||
      (decodedActive.startsWith('/douban') &&
        decodedActive.includes(`type=${typeMatch}`))
    );
  };

  return (
    <nav
      className='md:hidden fixed left-0 right-0 z-[600] bg-white/90 backdrop-blur-xl border-t border-gray-200/50 overflow-hidden dark:bg-gray-900/80 dark:border-gray-700/50'
      style={{
        /* 紧贴视口底部，同时在内部留出安全区高度 */
        bottom: 0,
        paddingBottom: 'env(safe-area-inset-bottom)',
        minHeight: 'calc(3.5rem + env(safe-area-inset-bottom))',
      }}
    >
      <ul className='flex items-center overflow-x-auto scrollbar-hide'>
        {navItems
          .filter((item) => {
            if (typeof window === 'undefined') return true;
            const disabled = (window as any).RUNTIME_CONFIG
              ?.DISABLED_CHANNELS as string[] | undefined;
            return !(item as any).key || !disabled?.includes((item as any).key);
          })
          .map((item) => {
          const active = isActive(item.href);
          return (
            <li
              key={item.href}
              className='flex-shrink-0'
              style={{ width: '20vw', minWidth: '20vw' }}
            >
              <Link
                href={item.href}
                prefetch={false}
                className='flex flex-col items-center justify-center w-full h-14 gap-1 text-xs'
              >
                <item.icon
                  className={`h-6 w-6 ${active
                    ? 'text-green-600 dark:text-green-400'
                    : 'text-gray-500 dark:text-gray-400'
                    }`}
                />
                <span
                  className={
                    active
                      ? 'text-green-600 dark:text-green-400'
                      : 'text-gray-600 dark:text-gray-300'
                  }
                >
                  {item.label}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};

export default MobileBottomNav;
