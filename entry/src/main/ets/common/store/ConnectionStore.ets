import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';
import { ConnectionProfile } from '../../model/ConnectionProfile';
import { UrlUtils } from '../utils/UrlUtils';

/**
 * 连接历史存储（Preferences 封装）。
 * 数据形状：connections = JSON.stringify(Array<ConnectionProfile.toStored()>)
 * 全量读写 + 内存缓存，规模小（<= MAX_HISTORY 条），不做增量同步。
 */
export class ConnectionStore {
  private pref: preferences.Preferences | null = null;

  private async getPref(context: common.Context): Promise<preferences.Preferences> {
    if (this.pref === null) {
      this.pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
    }
    return this.pref;
  }

  /** 读取全部历史（按最近使用倒序）。 */
  async loadAll(context: common.Context): Promise<ConnectionProfile[]> {
    const pref = await this.getPref(context);
    const text = await pref.get(AppConstants.KEY_CONNECTIONS, '[]');
    if (typeof text !== 'string') {
      return [];
    }
    let arr: Record<string, Object>[] = [];
    try {
      const parsed = JSON.parse(text) as Object;
      if (Array.isArray(parsed)) {
        arr = parsed as Record<string, Object>[];
      }
    } catch (e) {
      return [];
    }
    const out: ConnectionProfile[] = [];
    for (const item of arr) {
      const p = ConnectionProfile.fromStored(item);
      if (p !== null) {
        out.push(p);
      }
    }
    out.sort((a: ConnectionProfile, b: ConnectionProfile) => b.lastUsedAt - a.lastUsedAt);
    return out;
  }

  /** 按主机名（IP）去重的历史：同一 IP 仅保留最近使用的一条，时间倒序。 */
  async loadDistinctByIp(context: common.Context): Promise<ConnectionProfile[]> {
    const list = await this.loadAll(context);
    const byHost: Map<string, ConnectionProfile> = new Map<string, ConnectionProfile>();
    const order: string[] = [];
    for (const p of list) {
      const host = UrlUtils.hostOf(p.url);
      if (host.length === 0) {
        continue;
      }
      const existing = byHost.get(host);
      if (existing === undefined || p.lastUsedAt > existing.lastUsedAt) {
        if (existing === undefined) {
          order.push(host);
        }
        byHost.set(host, p);
      }
    }
    const out: ConnectionProfile[] = [];
    for (const host of order) {
      const p = byHost.get(host);
      if (p !== undefined) {
        out.push(p);
      }
    }
    out.sort((a: ConnectionProfile, b: ConnectionProfile) => b.lastUsedAt - a.lastUsedAt);
    return out;
  }

  /** 新增/更新一条（同 URL 覆盖并刷新 lastUsedAt），超上限裁剪最旧的。 */
  async upsert(context: common.Context, profile: ConnectionProfile): Promise<void> {
    const list = await this.loadAll(context);
    const idx = list.findIndex((p: ConnectionProfile) => p.url === profile.url);
    if (idx >= 0) {
      list.splice(idx, 1);
    }
    profile.lastUsedAt = Date.now();
    list.unshift(profile);
    if (list.length > AppConstants.MAX_HISTORY) {
      list.splice(AppConstants.MAX_HISTORY);
    }
    await this.save(context, list);
  }

  /** 删除一条。 */
  async remove(context: common.Context, url: string): Promise<void> {
    const list = await this.loadAll(context);
    const idx = list.findIndex((p: ConnectionProfile) => p.url === url);
    if (idx >= 0) {
      list.splice(idx, 1);
      await this.save(context, list);
    }
  }

  /** 清空历史。 */
  async clear(context: common.Context): Promise<void> {
    await this.save(context, []);
  }

  private async save(context: common.Context, list: ConnectionProfile[]): Promise<void> {
    const pref = await this.getPref(context);
    const stored: Record<string, Object>[] = [];
    for (const p of list) {
      stored.push(p.toStored());
    }
    await pref.put(AppConstants.KEY_CONNECTIONS, JSON.stringify(stored));
    await pref.flush();
  }
}
