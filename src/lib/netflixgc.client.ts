/* netflixgc 奈飞工厂频道：分类与网关 CATS 保持一致（分类走站内 POST JSON 接口）。
   客户端组件也能 import，不能引 @/lib/db。 */

export interface NetflixgcCategory {
  type_id: number;
  type_name: string;
}

export const NETFLIXGC_CATS: NetflixgcCategory[] = [
  { type_id: 1, type_name: '电影' },
  { type_id: 2, type_name: '连续剧' },
  { type_id: 3, type_name: '漫剧' },
  { type_id: 23, type_name: '综艺' },
  { type_id: 24, type_name: '纪录片' },
  { type_id: 57, type_name: '体育' },
  { type_id: 101, type_name: '热播榜' },
  { type_id: 102, type_name: '热搜榜' },
  { type_id: 103, type_name: '经典榜' },
  { type_id: 104, type_name: '冷门佳作榜' },
  { type_id: 105, type_name: '近期开播新剧' },
  { type_id: 106, type_name: '最新热播电影' },
];
