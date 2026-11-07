/* aqdlt 专用频道：分类由网关 /api/aqdlt/categories 动态下发（见 maccms-hub CATS）。
   本站暂无站内搜索，频道页不设搜索框。
   客户端组件也能 import，不能引 @/lib/db（见 duanju.client.ts 注释）。 */

export interface AqdltCategory {
  type_id: number;
  type_name: string;
  path: string;
}

/* 网关不可达时的保底分类（与 maccms-hub src/sites/aqdlt.js CATS 保持一致） */
export const AQDLT_CATS: AqdltCategory[] = [
  { type_id: 1, type_name: '最新更新', path: '' },
  { type_id: 2, type_name: '中國大陸', path: '/videos/category/cn.html' },
  { type_id: 3, type_name: '歐美', path: '/videos/category/west.html' },
  { type_id: 4, type_name: '日本', path: '/videos/category/jp.html' },
  { type_id: 5, type_name: '韓國', path: '/videos/category/kr.html' },
  { type_id: 6, type_name: '無碼', path: '/videos/tag/uncensored.html' },
  { type_id: 7, type_name: 'H動畫', path: '/videos/tag/cartoon.html' },
  { type_id: 8, type_name: '自拍', path: '/videos/tag/zipai.html' },
  { type_id: 9, type_name: '中文字幕', path: '/videos/tag/caption.html' },
  { type_id: 10, type_name: '学生', path: '/videos/tag/student.html' },
  { type_id: 11, type_name: '制服誘惑', path: '/videos/tag/uniform.html' },
  { type_id: 12, type_name: 'Cosplay', path: '/videos/tag/cosplay.html' },
  { type_id: 13, type_name: '無套中出', path: '/videos/tag/injection.html' },
];

export const AQDLT_STATE_KEY = 'aqdlt_state';
