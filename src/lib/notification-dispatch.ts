import type { IStorage, Notification } from './types';

// 通知通道（WebPush / Telegram）已随通知中心移除：保留分发入口 no-op，
// 避免改动全部存储适配器；通知写入 DB 的部分不受影响。
export async function dispatchNotificationChannels(
  _storage: IStorage,
  _userName: string,
  _notification: Notification
): Promise<void> {
  return;
}
