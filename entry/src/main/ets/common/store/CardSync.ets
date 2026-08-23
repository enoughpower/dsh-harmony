import { formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionStore } from './ConnectionStore';
import { ConnectionProfile } from '../../model/ConnectionProfile';
import { AppConstants } from '../constants/AppConstants';
import { LanDiscovery } from '../utils/LanDiscovery';
import { AppPrefs } from './AppPrefs';
import { PocketApi, LatestSessionInfo } from '../utils/PocketApi';

/**
 * 服务卡片同步：管理已添加卡片的 formId 列表，并在连接变化时刷新卡片数据。
 * 数据形状：form_ids = JSON.stringify(string[])（存 Preferences）
 */
export class CardSync {
  private static readonly KEY_FORM_IDS: string = 'form_ids';

  /** 卡片默认数据（无连接时） */
  static defaultData(): Record<string, string> {
    return {
      'appName': 'DSH Harmony',
      'lastUrl': '',
      'lastUrlDisplay': '扫码连接 DSH',
      'online': 'unknown',
      'lastUsedLabel': '',
      'sessionTitle': '',
      'sessionStatus': '',
      'sessionMeta': ''
    };
  }

  /** 相对时间标签：刚刚 / N 分钟前 / N 小时前 / 昨天 / N 天前 */
  static relativeLabel(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    const diff = Date.now() - ts;
    const minute = 60 * 1000;
    const hour = 60 * minute;
    const day = 24 * hour;
    if (diff < minute) {
      return '刚刚';
    }
    if (diff < hour) {
      return Math.floor(diff / minute) + ' 分钟前';
    }
    if (diff < day) {
      return Math.floor(diff / hour) + ' 小时前';
    }
    if (diff < 2 * day) {
      return '昨天';
    }
    return Math.floor(diff / day) + ' 天前';
  }

  /** 由最近连接生成卡片数据（含在线状态与相对时间）。在线探测失败按 unknown 呈现。 */
  static dataFrom(list: ConnectionProfile[], online: boolean = false, known: boolean = true,
    session: LatestSessionInfo | null = null): Record<string, string> {
    const base = CardSync.defaultData();
    if (list.length > 0) {
      const p = list[0];
      base['lastUrl'] = p.url;
      base['lastUrlDisplay'] = p.url.replace(/^https?:\/\//i, '');
      base['lastUsedLabel'] = CardSync.relativeLabel(p.lastUsedAt);
      base['online'] = known ? (online ? 'online' : 'offline') : 'unknown';
    }
    if (session !== null) {
      base['sessionTitle'] = session.title.length > 0 ? session.title : '（未命名会话）';
      base['sessionStatus'] = (session.running ? '进行中 · ' : '已结束 · ') + session.turns + ' 轮 · ' + session.steps + ' 步';
      base['sessionMeta'] = CardSync.relativeLabel(session.updatedAt);
    }
    return base;
  }

  static async saveFormId(context: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const ids = await CardSync.loadIds(context);
    if (!ids.includes(formId)) {
      ids.push(formId);
      await CardSync.saveIds(context, ids);
    }
  }

  static async removeFormId(context: common.Context, formId: string): Promise<void> {
    const ids = await CardSync.loadIds(context);
    const idx = ids.indexOf(formId);
    if (idx >= 0) {
      ids.splice(idx, 1);
      await CardSync.saveIds(context, ids);
    }
  }

  /** 用 Preferences 会话快照刷新所有已添加卡片（TaskMonitor 每次进度变化调用） */
  static async updateFormsFromSnapshot(context: common.Context): Promise<void> {
    const ids = await CardSync.loadIds(context);
    if (ids.length === 0) {
      return;
    }
    const snap = await AppPrefs.getSessionSnapshot(context);
    const base = CardSync.defaultData();
    if (snap.length > 0) {
      try {
        const obj = JSON.parse(snap) as Record<string, Object>;
        const title = String(obj['title'] ?? '');
        const turns = Number(obj['turns'] ?? 0);
        const steps = Number(obj['steps'] ?? 0);
        const running = obj['running'] === true;
        const updatedAt = Number(obj['updatedAt'] ?? 0);
        base['sessionTitle'] = title.length > 0 ? title : '（未命名会话）';
        base['sessionStatus'] = (running ? '进行中 · ' : '已结束 · ') + turns + ' 轮 · ' + steps + ' 步';
        base['sessionMeta'] = CardSync.relativeLabel(updatedAt);
      } catch (e) {
      }
    }
    const fd = formBindingData.createFormBindingData(base);
    for (const formId of ids) {
      formProvider.updateForm(formId, fd).catch(() => {
      });
    }
  }

  /** 用最近连接刷新所有已添加卡片（App 内建立新连接/打开首页时调用） */
  static async syncAll(context: common.Context): Promise<void> {
    const ids = await CardSync.loadIds(context);
    if (ids.length === 0) {
      return;
    }
    const list = await new ConnectionStore().loadAll(context);
    let online = false;
    let known = true;
    if (list.length > 0) {
      // 探测最近连接在线状态（弱探测：3081 可通）
      try {
        online = await LanDiscovery.isOnline(list[0].url, 1500);
      } catch (e) {
        known = false;
      }
    }
    // 最新会话（用 App 保存的令牌；无令牌/失败则留空）
    let session: LatestSessionInfo | null = null;
    if (list.length > 0) {
      try {
        const token = await AppPrefs.getString(context, AppPrefs.KEY_POCKET_TOKEN, '');
        if (token.length > 0) {
          const q = await PocketApi.queryWithToken(list[0].url, token);
          if (q.info !== null) {
            session = q.info;
          }
        }
      } catch (e) {
      }
    }
    const data = CardSync.dataFrom(list, online, known, session);
    const fd = formBindingData.createFormBindingData(data);
    for (const formId of ids) {
      formProvider.updateForm(formId, fd).catch((e: BusinessError) => {
        console.warn('CardSync updateForm failed: ' + e.message);
      });
    }
  }

  /** 从快照还原 LatestSessionInfo（首页/小组件读取统一数据源） */
  static async sessionFromSnapshot(context: common.Context): Promise<LatestSessionInfo | null> {
    const snap = await AppPrefs.getSessionSnapshot(context);
    if (snap.length === 0) {
      return null;
    }
    try {
      const obj = JSON.parse(snap) as Record<string, Object>;
      const info: LatestSessionInfo = {
        title: String(obj['title'] ?? ''),
        updatedAt: Number(obj['updatedAt'] ?? 0),
        running: obj['running'] === true,
        turns: Number(obj['turns'] ?? 0),
        steps: Number(obj['steps'] ?? 0)
      };
      return info;
    } catch (e) {
      return null;
    }
  }

  private static async loadIds(context: common.Context): Promise<string[]> {
    const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
    const raw = await pref.get(CardSync.KEY_FORM_IDS, '[]');
    if (typeof raw !== 'string') {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        const arr = parsed as string[];
        const out: string[] = [];
        for (const item of arr) {
          if (typeof item === 'string' && item.length > 0) {
            out.push(item);
          }
        }
        return out;
      }
    } catch (e) {
      // 损坏数据按空处理
    }
    return [];
  }

  private static async saveIds(context: common.Context, ids: string[]): Promise<void> {
    const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
    await pref.put(CardSync.KEY_FORM_IDS, JSON.stringify(ids));
    await pref.flush();
  }
}
