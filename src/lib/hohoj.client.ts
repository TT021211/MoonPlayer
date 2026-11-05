/* HoHoJ 频道：分类由网关 /api/hohoj/categories 动态下发（见 maccms-hub CATS）。
   客户端组件也能 import，不能引 @/lib/db（见 duanju.client.ts 注释）。 */

export interface HohojCategory {
  type_id: number;
  type_name: string;
  path: string;
}

/* 网关不可达时的保底分类（与 maccms-hub src/sites/hohoj.js CATS 保持一致） */
export const HOHOJ_CATS: HohojCategory[] = [
  { type_id: 1, type_name: '最新更新', path: '' },
  { type_id: 2, type_name: '無碼', path: '/search?type=uncensored' },
  { type_id: 3, type_name: '中文字幕', path: '/search?type=chinese' },
  { type_id: 4, type_name: '歐美', path: '/search?type=europe' },
  { type_id: 5, type_name: '有碼', path: '/search?type=censored' },
  { type_id: 6, type_name: '制服誘惑', path: '/main_ctg?id=4' },
  { type_id: 7, type_name: '巨乳美乳', path: '/main_ctg?id=9' },
  { type_id: 8, type_name: '角色劇情', path: '/main_ctg?id=6' },
  { type_id: 9, type_name: '出軌', path: '/main_ctg?id=7' },
  { type_id: 10, type_name: '亂倫', path: '/main_ctg?id=8' },
  { type_id: 11, type_name: '多P群交', path: '/main_ctg?id=5' },
  { type_id: 12, type_name: '主奴調教', path: '/main_ctg?id=3' },
  { type_id: 13, type_name: '絲襪美腿', path: '/main_ctg?id=1' },
];

export const HOHOJ_STATE_KEY = 'hohoj_state';
