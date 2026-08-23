import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';

/**
 * 应用级布尔开关（Preferences 封装）。
 * 约定：key 无前缀意义即全局设置；默认值以 get 参数为准。
 */
export class AppPrefs {
  static readonly KEY_AUTO_DISCOVER: string = 'auto_discover';
  /** 进入 App 自动连接最近一次使用的 IP（替代旧的自动扫描开关） */
  static readonly KEY_AUTO_CONNECT: string = 'auto_connect_latest';
  /** dsh-pocket 局域网访问 PIN（默认 11111111） */
  static readonly KEY_LAN_PIN: string = 'lan_pin';
  static readonly DEFAULT_LAN_PIN: string = '11111111';
  /** dsh-pocket 访问令牌（网页 Cookie 提取/登录所得；供服务卡片复用） */
  static readonly KEY_POCKET_TOKEN: string = 'pocket_token';
  /** 任务监听开关（默认开）：实况窗 + 后台轮询数据源 */
  static readonly KEY_TASK_MONITOR: string = 'task_monitor';
  /** 会话快照（前台服务写入，小组件/首页读取） */
  static readonly KEY_SESSION_SNAPSHOT: string = 'session_snapshot';

  static async getBool(context: common.Context, key: string, def: boolean): Promise<boolean> {
    try {
      const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
      const raw = await pref.get(key, def);
      return raw === true;
    } catch (e) {
      return def;
    }
  }

  static async setBool(context: common.Context, key: string, value: boolean): Promise<void> {
    const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
    await pref.put(key, value);
    await pref.flush();
  }

  static async getString(context: common.Context, key: string, def: string): Promise<string> {
    try {
      const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
      const raw = await pref.get(key, def);
      return typeof raw === 'string' ? raw : def;
    } catch (e) {
      return def;
    }
  }

  static async setString(context: common.Context, key: string, value: string): Promise<void> {
    const pref = await preferences.getPreferences(context, AppConstants.STORE_NAME);
    await pref.put(key, value);
    await pref.flush();
  }

  /** 写入会话快照（最新会话轻量字段 JSON） */
  static async setSessionSnapshot(context: common.Context, snapshot: string): Promise<void> {
    await AppPrefs.setString(context, AppPrefs.KEY_SESSION_SNAPSHOT, snapshot);
  }

  /** 读取会话快照 JSON（无则空串） */
  static async getSessionSnapshot(context: common.Context): Promise<string> {
    return await AppPrefs.getString(context, AppPrefs.KEY_SESSION_SNAPSHOT, '');
  }
}
