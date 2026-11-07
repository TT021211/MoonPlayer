/* bjcam 频道：分类与网关 CATS 保持一致（WP 标准翻页）。
   客户端组件也能 import，不能引 @/lib/db。 */

export interface BjcamCategory {
  type_id: number;
  type_name: string;
}

export const BJCAM_CATS: BjcamCategory[] = [
  { type_id: 1, type_name: '最新发布' },
  { type_id: 2, type_name: 'KOREAN BJ' },
  { type_id: 3, type_name: 'CHINESE GIRL' },
];
