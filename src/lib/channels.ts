// 导航频道定义：key 稳定不变，供后台频道开关 + 两端导航共用。
// 关闭的频道不在导航展示（直接访问 URL 不拦截）。
export interface ChannelDef {
  key: string;
  label: string;
}

export const NAV_CHANNELS: ChannelDef[] = [
  { key: 'movie', label: '电影' },
  { key: 'tv', label: '剧集' },
  { key: 'anime', label: '动漫' },
  { key: 'hanime', label: '深夜剧场' },
  { key: 'aqdlt', label: '心动剧场' },
  { key: 'hohoj', label: 'HoHo剧场' },
  { key: 'show', label: '综艺' },
  { key: 'kinostream', label: 'KinoStream' },
  { key: 'bjcam', label: 'BJ剧场' },
  { key: 'custom', label: '自定义' },
  { key: 'browse', label: '源浏览' },
];

export function isChannelDisabled(
  disabledChannels: string[] | undefined,
  key: string
): boolean {
  return Array.isArray(disabledChannels) && disabledChannels.includes(key);
}
