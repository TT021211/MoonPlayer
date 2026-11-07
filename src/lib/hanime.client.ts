/* hanime1-maccms hanime 专用频道：纯静态分类表（与采集端 server.js CATS 保持一致）。
   客户端组件也能 import，不能引 @/lib/db（见 duanju.client.ts 注释）。 */

export interface HanimeCategory {
  type_id: number;
  type_name: string;
  genre: string;
  sort: string;
}

export const HANIME_CATS: HanimeCategory[] = [
  { type_id: 1, type_name: '最新里番', genre: '裏番', sort: '最新上市' },
  { type_id: 2, type_name: '最新上市', genre: '', sort: '最新上市' },
  { type_id: 3, type_name: '最新上傳', genre: '', sort: '最新上傳' },
  { type_id: 4, type_name: '裏番', genre: '裏番', sort: '' },
  { type_id: 5, type_name: '泡麵番', genre: '泡麵番', sort: '' },
  { type_id: 6, type_name: 'Motion Anime', genre: 'Motion Anime', sort: '' },
  { type_id: 7, type_name: '3DCG', genre: '3DCG', sort: '' },
  { type_id: 8, type_name: '2.5D', genre: '2.5D', sort: '' },
  { type_id: 9, type_name: '2D動畫', genre: '2D動畫', sort: '' },
  { type_id: 10, type_name: 'AI生成', genre: 'AI生成', sort: '' },
  { type_id: 11, type_name: 'MMD', genre: 'MMD', sort: '' },
  { type_id: 12, type_name: 'Cosplay', genre: 'Cosplay', sort: '' },
  { type_id: 13, type_name: '新番預告', genre: '新番預告', sort: '' },
];

/* 判断一个 CMS 分类是否属于 hanime 源（用于自动发现采集源） */
export function isHanimeTypeName(typeName: string): boolean {
  if (!typeName) return false;
  const t = typeName.toLowerCase();
  return (
    t.includes('裏番') ||
    t.includes('里番') ||
    t.includes('泡麵番') ||
    t.includes('泡面番') ||
    t.includes('motion anime') ||
    t.includes('3dcg') ||
    t.includes('2.5d') ||
    t.includes('2d動畫') ||
    t.includes('2d动画') ||
    t.includes('ai生成') ||
    t.includes('mmd') ||
    t.includes('cosplay') ||
    t.includes('新番預告') ||
    t.includes('新番预告')
  );
}

export const HANIME_STATE_KEY = 'hanime_state';
