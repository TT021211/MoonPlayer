'use client';

import { History } from 'lucide-react';
import { useState } from 'react';

import PlayRecordsPanel from './PlayRecordsPanel';

// 右上角播放记录入口：点击打开全部播放记录弹窗，点条目继续观看。
export default function PlayHistoryButton() {
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type='button'
        onClick={() => setOpen(true)}
        title='播放记录'
        aria-label='播放记录'
        className='w-10 h-10 p-2 rounded-full flex items-center justify-center text-gray-600 hover:bg-gray-200/50 dark:text-gray-300 dark:hover:bg-gray-700/50 transition-colors'
      >
        <History className='w-full h-full' />
      </button>
      {open && (
        <PlayRecordsPanel isOpen={open} onClose={() => setOpen(false)} />
      )}
    </>
  );
}
