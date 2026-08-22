import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmonyTest';

export default class TestAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'TestAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // UI 测试直接启动主应用 EntryAbility 断言，TestAbility 无需承载页面
    hilog.info(DOMAIN, TAG, 'TestAbility onWindowStageCreate');
  }
}
