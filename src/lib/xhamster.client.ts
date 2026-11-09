/* xhamster 频道：分类与网关 CATS 保持一致。
   客户端组件也能 import，不能引 @/lib/db。 */

export interface XhamsterCategory {
  type_id: number;
  type_name: string;
}

export const XHAMSTER_CATS: XhamsterCategory[] = [
  { type_id: 1, type_name: '日本' },
  { type_id: 2, type_name: '亚洲' },
  { type_id: 3, type_name: 'JAV' },
  { type_id: 4, type_name: '素人' },
  { type_id: 5, type_name: '自拍' },
  { type_id: 6, type_name: '拉拉' },
  { type_id: 7, type_name: '肛交' },
  { type_id: 8, type_name: '中出' },
  { type_id: 9, type_name: '妈妈' },
  { type_id: 10, type_name: '熟女' },
  { type_id: 11, type_name: '口交' },
  { type_id: 12, type_name: 'POV' },
];
