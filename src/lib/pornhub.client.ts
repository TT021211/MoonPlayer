/* pornhub 频道：分类与网关 CATS 保持一致。
   客户端组件也能 import，不能引 @/lib/db。 */

export interface PornhubCategory {
  type_id: number;
  type_name: string;
}

export const PORNHUB_CATS: PornhubCategory[] = [
  { type_id: 1, type_name: '日本人' },
  { type_id: 2, type_name: '熟女' },
  { type_id: 3, type_name: '辣妈' },
  { type_id: 4, type_name: '巨乳' },
  { type_id: 5, type_name: '女同' },
  { type_id: 6, type_name: '爆菊' },
  { type_id: 7, type_name: '3P' },
  { type_id: 8, type_name: '内射' },
  { type_id: 9, type_name: '潮吹' },
  { type_id: 10, type_name: '捆绑' },
  { type_id: 11, type_name: '日漫' },
  { type_id: 12, type_name: '少女' },
];
