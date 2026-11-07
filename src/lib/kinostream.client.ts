/* kinostream 频道：分类与网关 CATS 保持一致（上游分类页一次全量，网关按页切分）。
   客户端组件也能 import，不能引 @/lib/db。 */

export interface KinostreamCategory {
  type_id: number;
  type_name: string;
}

export const KINOSTREAM_CATS: KinostreamCategory[] = [
  { type_id: 1, type_name: '最新上架' },
  { type_id: 2, type_name: '特別推薦' },
  { type_id: 3, type_name: '感官世界' },
  { type_id: 4, type_name: 'B級特區' },
  { type_id: 5, type_name: '大眾娛樂' },
  { type_id: 6, type_name: '午夜狂熱' },
];
