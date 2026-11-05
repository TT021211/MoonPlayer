export const yellowWords = [
  '伦理片',
  '福利',
  '里番动漫',
  '门事件',
  '萝莉少女',
  '制服诱惑',
  '国产传媒',
  'cosplay',
  '黑丝诱惑',
  '无码',
  '日本无码',
  '有码',
  '日本有码',
  'SWAG',
  '网红主播',
  '色情片',
  '同性片',
  '福利视频',
  '福利片',
  '写真热舞',
  '倫理片',
  '理论片',
  '韩国伦理',
  '港台三级',
  '电影解说',
  '伦理',
  '日本伦理',
];

/** 前台开关存储键（localStorage），默认开启过滤 */
export const YELLOW_FILTER_STORAGE_KEY = 'yellowFilterEnabled';

/**
 * 是否应用黄色过滤。优先级：请求参数 ?yellowFilter= > 全局开关。
 * - yellowFilter=1/true：强制过滤；=0/false：强制不过滤
 * - 无参数时：默认过滤（全局 DisableYellowFilter=true 才关闭）
 */
export function shouldApplyYellowFilter(
  param: string | null,
  disableYellowFilter?: boolean
): boolean {
  if (param === '1' || param === 'true') return true;
  if (param === '0' || param === 'false') return false;
  return !disableYellowFilter;
}

/** 按 type_name 过滤黄词内容（大小写敏感，与现有各接口行为一致） */
export function filterYellowByTypeName<T extends { type_name?: string }>(
  items: T[]
): T[] {
  return items.filter(
    (item) =>
      !yellowWords.some((word) => (item.type_name || '').includes(word))
  );
}

/** 浏览器端读取前台开关（默认 true；SSR 时回落 true） */
export function loadYellowFilterEnabled(): boolean {
  if (typeof window === 'undefined') return true;
  const saved = window.localStorage.getItem(YELLOW_FILTER_STORAGE_KEY);
  if (saved === '0' || saved === 'false') return false;
  return true;
}
