/* MissAV 里番频道：分类由网关 /api/missav/categories 动态下发（见 maccms-hub CATS）。
   客户端组件也能 import，不能引 @/lib/db（见 duanju.client.ts 注释）。 */

export interface MissavCategory {
  type_id: number;
  type_name: string;
  path: string;
}

/* 网关不可达时的保底分类（与 maccms-hub src/sites/missav.js CATS 保持一致） */
export const MISSAV_CATS: MissavCategory[] = [
  { type_id: 1, type_name: '最新更新', path: '/new' },
  { type_id: 2, type_name: '新作上市', path: '/release' },
  { type_id: 3, type_name: '無碼流出', path: '/uncensored-leak' },
  { type_id: 4, type_name: '中文字幕', path: '/chinese-subtitle' },
  { type_id: 5, type_name: '今日熱門', path: '/dm301/today-hot' },
  { type_id: 6, type_name: '本週熱門', path: '/dm170/weekly-hot' },
  { type_id: 7, type_name: '本月熱門', path: '/dm273/monthly-hot' },
  { type_id: 8, type_name: 'VR', path: '/genres/VR' },
  { type_id: 9, type_name: 'FC2', path: '/dm597/fc2' },
  { type_id: 10, type_name: '東京熱', path: '/dm42/tokyohot' },
  { type_id: 11, type_name: '一本道', path: '/dm4551174/1pondo' },
  { type_id: 12, type_name: '加勒比海', path: '/dm6840521/caribbeancom' },
  { type_id: 13, type_name: '麻豆傳媒', path: '/dm63/madou' },
];

/* 判断一个 CMS 分类是否属于 missav 源（用于自动发现采集源） */
export function isMissavTypeName(typeName: string): boolean {
  if (!typeName) return false;
  const t = typeName.toLowerCase();
  return (
    t.includes('最新更新') ||
    t.includes('新作上市') ||
    t.includes('無碼流出') ||
    t.includes('无码流出') ||
    t.includes('中文字幕') ||
    t.includes('今日熱門') ||
    t.includes('今日热门') ||
    t.includes('本週熱門') ||
    t.includes('本周热门') ||
    t.includes('本月熱門') ||
    t.includes('本月热门') ||
    t.includes('東京熱') ||
    t.includes('东京热') ||
    t.includes('一本道') ||
    t.includes('加勒比') ||
    t.includes('麻豆')
  );
}

export const MISSAV_STATE_KEY = 'missav_state';
