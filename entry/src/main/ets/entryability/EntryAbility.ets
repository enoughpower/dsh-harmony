import { AbilityConstant, UIAbility, Want, Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 主 Ability。
 * - 系统栏（状态栏/导航栏）颜色对齐页面背景资源色：浅色 #F7F8FA / 深色 #121417（实色，非透明）
 *   ——避免安全区与页面背景色不一致；不启用全屏（内容保持自动避让，防重叠/黑边）
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
    // 系统栏对齐页面背景（实色，非透明；不设全屏，内容默认避让）
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
   * 系统栏颜色（确定性硬编码，不依赖资源解析时序）：
   * 浅色模式：背景 #F7F8FA + 内容纯黑；深色模式：背景 #121417 + 内容纯白。
   */
  private applySystemBarStyle(): void {
    if (this.winStage === null) {
      return;
    }
    try {
      const win = this.winStage.getMainWindowSync();
      const dark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      win.setWindowSystemBarProperties({
        statusBarColor: dark ? '#121417' : '#F7F8FA',
        navigationBarColor: dark ? '#121417' : '#F7F8FA',
        statusBarContentColor: dark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: dark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', (e as Error).message);
    }
  }
}
