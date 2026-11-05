'use client';

import { useState } from 'react';

import CapsuleSwitch from '@/components/CapsuleSwitch';

export interface CrumbGroup {
  /** 分组标题，如 主題 / 標籤 / 地區；空为不分组 */
  label: string;
  items: Array<{ id: string; name: string }>;
}

/** 把带 group 字段的分类折成面包屑分组（无 group 的归入“分类”） */
export function buildCrumbGroups<
  T extends { id: string; name: string; group?: string },
>(categories: T[]): CrumbGroup[] {
  const map = new Map<string, Array<{ id: string; name: string }>>();
  const order: string[] = [];
  for (const c of categories) {
    const g = c.group || '分类';
    if (!map.has(g)) {
      map.set(g, []);
      order.push(g);
    }
    map.get(g)!.push({ id: c.id, name: c.name });
  }
  return order.map((label) => ({ label, items: map.get(label)! }));
}

interface CategoryBreadcrumbProps {
  groups: CrumbGroup[];
  selectedId: string;
  /** 面包屑根节点文案 */
  rootLabel?: string;
  /** 总条数小于等于此值时直接平铺，不收起 */
  inlineThreshold?: number;
  onChange: (id: string) => void;
}

/**
 * 分类面包屑：选中路径 + 点一下展开分组面板。
 * 小列表（默认 ≤12 条且单组）直接平铺胶囊，保持老体验。
 */
export default function CategoryBreadcrumb({
  groups,
  selectedId,
  rootLabel = '全部分类',
  inlineThreshold = 12,
  onChange,
}: CategoryBreadcrumbProps) {
  const [expanded, setExpanded] = useState(false);
  const total = groups.reduce((n, g) => n + g.items.length, 0);
  const selectedName =
    groups.flatMap((g) => g.items).find((c) => c.id === selectedId)?.name || '';

  if (groups.length === 0 || total === 0) return null;

  // 小列表直接平铺胶囊（保持老体验）；大列表走面包屑 + 展开
  const canInline =
    total <= 40 && (groups.length === 1 || total <= inlineThreshold);
  if (!expanded && canInline) {
    const all = groups.flatMap((g) => g.items);
    return (
      <div className='flex px-4'>
        <CapsuleSwitch
          options={all.map((c) => ({ label: c.name, value: c.id }))}
          active={selectedId}
          onChange={onChange}
        />
      </div>
    );
  }

  return (
    <div className='px-4'>
      {/* 面包屑轨 */}
      <div className='flex items-center gap-2 text-sm'>
        <button
          type='button'
          onClick={() => setExpanded((v) => !v)}
          className='inline-flex items-center gap-1.5 rounded-full border border-gray-200 bg-white px-3 py-1.5 font-medium text-gray-700 shadow-sm hover:border-red-300 hover:text-red-600 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-200 dark:hover:border-red-500 dark:hover:text-red-400'
          aria-expanded={expanded}
        >
          <span className='text-gray-400 dark:text-gray-500'>{rootLabel}</span>
          {selectedName && (
            <>
              <span className='text-gray-300 dark:text-gray-600'>/</span>
              <span className='max-w-[12rem] truncate font-semibold text-red-600 dark:text-red-400'>
                {selectedName}
              </span>
            </>
          )}
          <svg
            className={`h-3.5 w-3.5 transition-transform ${expanded ? 'rotate-180' : ''}`}
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            strokeWidth='2'
          >
            <path d='M6 9l6 6 6-6' />
          </svg>
        </button>
        <span className='text-xs text-gray-400 dark:text-gray-500'>
          共 {total} 个分类
        </span>
      </div>

      {/* 展开面板：按组展示 */}
      {expanded && (
        <div className='mt-3 space-y-3 rounded-xl border border-gray-200/70 bg-white/70 p-3 dark:border-gray-700/70 dark:bg-gray-800/70'>
          {groups.map((g) => (
            <div key={g.label || 'all'}>
              {groups.length > 1 && g.label && (
                <div className='mb-1.5 px-1 text-xs font-medium text-gray-500 dark:text-gray-400'>
                  {g.label}（{g.items.length}）
                </div>
              )}
              <div className='flex flex-wrap gap-1.5'>
                {g.items.map((c) => {
                  const active = c.id === selectedId;
                  return (
                    <button
                      key={c.id}
                      type='button'
                      onClick={() => {
                        onChange(c.id);
                        setExpanded(false);
                      }}
                      className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors sm:text-sm ${
                        active
                          ? 'bg-gradient-to-r from-orange-500 to-red-600 text-white shadow'
                          : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
                      }`}
                    >
                      {c.name}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
