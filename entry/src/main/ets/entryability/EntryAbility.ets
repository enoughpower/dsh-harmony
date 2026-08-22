import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 主 Ability。
 * - 沉浸式：全屏布局 + 透明系统栏，内容色随系统深浅色
 * - 服务卡片点击：解析 want.parameters.dshUrl → AppStorage.pendingDshUrl → Index 消费跳转
 */
export default class EntryAbility extends UIAbility {
  private winStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate. reason=%{public}d', launchParam.launchReason);
    this.consumeCardUrl(want);
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onNewWant.');
    this.consumeCardUrl(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate.');
    this.winStage = windowStage;
    try {
      const win = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', (e as Error).message);
    }
    this.applySystemBarStyle();
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load pages/Index. code=%{public}d message=%{public}s',
          err.code, err.message);
        return;
      }
      hilog.info(DOMAIN, TAG, 'pages/Index loaded.');
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate: colorMode=%{public}d', newConfig.colorMode ?? -1);
    this.applySystemBarStyle();
  }

  onWindowStageDestroy(): void {
    this.winStage = null;
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy.');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground.');
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

  /** 系统栏透明 + 内容色跟随深浅色 */
  private applySystemBarStyle(): void {
    if (this.winStage === null) {
      return;
    }
    try {
      const win = this.winStage.getMainWindowSync();
      const dark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#FFFFFF' : '#1A1A1A',
        navigationBarContentColor: dark ? '#FFFFFF' : '#1A1A1A'
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', (e as Error).message);
    }
  }
}
