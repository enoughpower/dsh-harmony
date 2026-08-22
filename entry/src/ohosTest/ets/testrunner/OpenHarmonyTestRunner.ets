import hilog from '@ohos.hilog';
import { TestRunner } from '@ohos.application.testRunner';
import { AbilityDelegatorRegistry } from '@kit.TestKit';

let abilityDelegator: AbilityDelegatorRegistry.AbilityDelegator;
let abilityDelegatorArguments: AbilityDelegatorRegistry.AbilityDelegatorArgs;

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(0x0000, 'testTag', 'OpenHarmonyTestRunner OnPrepare');
  }

  onRun(): void {
    hilog.info(0x0000, 'testTag', 'OpenHarmonyTestRunner onRun');
    abilityDelegator = AbilityDelegatorRegistry.getAbilityDelegator();
    abilityDelegatorArguments = AbilityDelegatorRegistry.getArguments();
    const abilityDelegatorRegistry = AbilityDelegatorRegistry;
    const testAbilityName = abilityDelegatorArguments.parameters['-p'] ?? abilityDelegatorArguments.bundleName + '_test';
    if (testAbilityName !== null) {
      const want = {
        bundleName: abilityDelegatorArguments.bundleName,
        abilityName: testAbilityName
      };
      abilityDelegator.startAbility(want, (err) => {
        hilog.info(0x0000, 'testTag', 'startAbility err: %{public}s', JSON.stringify(err));
      });
    }
    abilityDelegator.executeAbilityTest('test', (result) => {
      hilog.info(0x0000, 'testTag', 'executeAbilityTest result: %{public}s', JSON.stringify(result));
      abilityDelegator.finishTest('finish', 0, () => {});
    });
  }
}
