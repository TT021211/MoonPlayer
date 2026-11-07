'use client';

import Link from 'next/link';

import { BackButton } from './BackButton';
import PlayHistoryButton from './PlayHistoryButton';
import { useSite } from './SiteProvider';
import { ThemeToggle } from './ThemeToggle';
import { UpdateNotification } from './UpdateNotification';
import { UserMenu } from './UserMenu';

interface MobileHeaderProps {
  showBackButton?: boolean;
}

const MobileHeader = ({ showBackButton = false }: MobileHeaderProps) => {
  const { siteName } = useSite();
  return (
    <header
      className='md:hidden fixed top-0 left-0 right-0 z-[999] w-full bg-white/70 backdrop-blur-xl border-b border-gray-200/50 shadow-sm dark:bg-gray-900/70 dark:border-gray-700/50'
      style={{ paddingTop: 'var(--safe-top)' }}
    >
      <div className='h-12 flex items-center gap-1 px-4'>
        {/* 左侧：搜索按钮、返回按钮（固定宽度，不参与挤压） */}
        <div className='flex items-center gap-2 flex-shrink-0'>
          <Link
            href='/search'
            className='w-10 h-10 p-2 rounded-full flex items-center justify-center text-gray-600 hover:bg-gray-200/50 dark:text-gray-300 dark:hover:bg-gray-700/50 transition-colors'
          >
            <svg
              className='w-full h-full'
              fill='none'
              stroke='currentColor'
              viewBox='0 0 24 24'
              xmlns='http://www.w3.org/2000/svg'
            >
              <path
                strokeLinecap='round'
                strokeLinejoin='round'
                strokeWidth={2}
                d='M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z'
              />
            </svg>
          </Link>
          {showBackButton && <BackButton />}
        </div>

        {/* 中间：Logo（弹性居中，空间不足时截断，永不和两侧按钮重叠；
            之前 absolute 居中在窄屏下会压到右侧图标） */}
        <div className='flex-1 min-w-0 text-center'>
          <Link
            href='/'
            prefetch={false}
            className='block truncate text-xl font-bold text-green-600 tracking-tight hover:opacity-80 transition-opacity duration-200'
          >
            {siteName}
          </Link>
        </div>

        {/* 右侧按钮（固定宽度，不参与挤压） */}
        <div className='flex items-center gap-1 flex-shrink-0'>
          <ThemeToggle />
          <PlayHistoryButton />
          <UserMenu />
          <UpdateNotification />
        </div>
      </div>
    </header>
  );
};

export default MobileHeader;
