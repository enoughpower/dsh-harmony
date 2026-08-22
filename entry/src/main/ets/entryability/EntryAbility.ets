import { AbilityConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 主 Ability。
 * - 窗口保持系统默认（不自定义全屏/系统栏，避免与状态栏重叠或黑边；深色由 dark 资源适配）
 * - 服务卡片点击：解析 want.parameters.dshUrl → AppStorage.pendingDshUrl → Index 消费跳转
 */
export default class EntryAbility extends UIAbility {
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
    // 窗口保持系统默认行为（不设全屏、不设透明系统栏）：
    //   - 全屏会与状态栏内容重叠（真机验证）
    //   - 透明系统栏在非全屏下露出黑色窗口底色（真机验证）
    // 状态栏/导航栏按系统默认渲染，深色适配由 dark 资源完成。
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
    // 深色适配由 dark 资源自动完成，仅记录日志
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate: colorMode=%{public}d', newConfig.colorMode ?? -1);
  }

  onWindowStageDestroy(): void {
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

}
