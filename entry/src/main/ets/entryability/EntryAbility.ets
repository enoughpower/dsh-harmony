import { AbilityConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PushToken } from '../common/store/PushToken';
import { WindowBar } from '../common/utils/WindowBar';
import { DeviceUtils } from '../common/utils/DeviceUtils';
import { FeatureFlags } from '../common/config/FeatureFlags';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 主 Ability。
 * - 全局沉浸式：全屏布局 + 透明状态栏/导航栏（所有页面统一，内容自行让出状态栏）
 * - 服务卡片点击：解析 want.parameters.dshUrl → AppStorage.pendingDshUrl → Index 消费跳转
 */
export default class EntryAbility extends UIAbility {
  private winStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate. reason=%{public}d', launchParam.launchReason);
    this.consumeCardUrl(want);
    // Push Kit：获取设备推送令牌并上报电脑端（未在 AGC 开通时静默，报 1000900012）
    if (FeatureFlags.PUSH_ENABLED) {
      PushToken.ensureAndReport(this.context).catch(() => {
      });
    }
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onNewWant.');
    this.consumeCardUrl(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate.');
    this.winStage = windowStage;
    // 系统栏对齐页面背景（实色，非透明；不设全屏，内容默认避让）
    this.applySystemBarStyle();
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load pages/Index. code=%{public}d message=%{public}s',
          err.code, err.message);
        return;
      }
      // 冷启动时序兜底：内容挂载后再补一次系统栏（首帧前 config 可能未解析）
      this.applySystemBarStyle();
      hilog.info(DOMAIN, TAG, 'pages/Index loaded.');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate: colorMode=%{public}d', newConfig.colorMode ?? -1);
    this.applySystemBarStyle();
    // 深浅色同步给 WebShell（ResourceManager 解析,与系统栏一致）
    const isDark = WindowBar.isDark(this.context);
    AppStorage.setOrCreate('osThemeIsDark', isDark);
  }

  onWindowStageDestroy(): void {
    this.winStage = null;
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy.');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground.');
    // 后台切深浅色不回调 onConfigurationUpdate，回前台时强制刷新系统栏颜色
    this.applySystemBarStyle();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground.');
  }

  /** 服务卡片点击直达：把 dshUrl 放进 AppStorage，Index 页面消费 */
  private consumeCardUrl(want: Want): void {
    const url = want.parameters?.['dshUrl'];
    if (typeof url === 'string' && url.length > 0) {
      AppStorage.setOrCreate('pendingDshUrl', url);
      hilog.info(DOMAIN, TAG, 'card click pending url: %{public}s', url);
    }
  }

  /**
   * 全局沉浸式（所有页面统一）：全屏布局 + 透明状态栏/导航栏，
   * 内容色随深浅色（浅色纯黑 / 深色纯白）；页面内容自行让出状态栏（不挡）。
   */
  private applySystemBarStyle(): void {
    if (this.winStage === null) {
      return;
    }
    try {
      const win = this.winStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
      // 大屏(平板/折叠屏展开)：允许横竖屏自动旋转；普通手机：锁定竖屏
      try {
        win.setPreferredOrientation((DeviceUtils.isTablet() || DeviceUtils.isLargeDisplay()) ? window.Orientation.AUTO_ROTATION : window.Orientation.PORTRAIT);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setPreferredOrientation failed: %{public}s', (e as Error).message);
      }
      // ResourceManager 解析主题色(跟随系统),不依赖 config.colorMode(冷启动可能 NOT_SET)
      const dark = WindowBar.isDark(this.context);
      AppStorage.setOrCreate('osThemeIsDark', dark);
      hilog.info(DOMAIN, TAG, 'applySystemBar dark=%{public}s', String(dark));
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', (e as Error).message);
    }
  }
}
