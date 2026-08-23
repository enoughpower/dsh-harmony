import { LatestSessionInfo } from '../utils/PocketApi';

/** 会话状态订阅回调 */
type SessionListener = (info: LatestSessionInfo | null) => void;

/**
 * App 内统一会话数据源（内存单例）：
 * TaskMonitor（前台服务）每次进度变化写入；首页等 UI 订阅实时更新。
 */
export class AppSessionState {
  private static current: LatestSessionInfo | null = null;
  private static listeners: SessionListener[] = [];

  static get(): LatestSessionInfo | null {
    return AppSessionState.current;
  }

  static update(info: LatestSessionInfo | null): void {
    AppSessionState.current = info;
    for (const l of AppSessionState.listeners) {
      try {
        l(info);
      } catch (e) {
      }
    }
  }

  static subscribe(listener: SessionListener): () => void {
    AppSessionState.listeners.push(listener);
    return () => {
      const idx = AppSessionState.listeners.indexOf(listener);
      if (idx >= 0) {
        AppSessionState.listeners.splice(idx, 1);
      }
    };
  }

  static clear(): void {
    AppSessionState.listeners = [];
  }
}
