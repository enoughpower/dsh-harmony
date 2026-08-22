import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants } from '../constants/AppConstants';

/**
 * 应用级布尔开关（Preferences 封装）。
 * 约定：key 无前缀意义即全局设置；默认值以 get 参数为准。
 */
export class AppPrefs {
  static readonly KEY_AUTO_DISCOVER: string = 'auto_discover';

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
}
