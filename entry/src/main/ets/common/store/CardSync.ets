import { formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionStore } from './ConnectionStore';
import { ConnectionProfile } from '../../model/ConnectionProfile';
import { AppConstants } from '../constants/AppConstants';

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
      'lastUrlDisplay': '扫码连接 DSH'
    };
  }

  /** 由最近连接生成卡片数据 */
  static dataFrom(list: ConnectionProfile[]): Record<string, string> {
    if (list.length > 0) {
      return {
        'appName': 'DSH Harmony',
        'lastUrl': list[0].url,
        'lastUrlDisplay': list[0].url.replace(/^https?:\/\//i, '')
      };
    }
    return CardSync.defaultData();
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

  /** 用最近连接刷新所有已添加卡片（App 内建立新连接时调用） */
  static async syncAll(context: common.Context): Promise<void> {
    const ids = await CardSync.loadIds(context);
    if (ids.length === 0) {
      return;
    }
    const list = await new ConnectionStore().loadAll(context);
    const data = CardSync.dataFrom(list);
    const fd = formBindingData.createFormBindingData(data);
    for (const formId of ids) {
      formProvider.updateForm(formId, fd).catch((e: BusinessError) => {
        console.warn('CardSync updateForm failed: ' + e.message);
      });
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
