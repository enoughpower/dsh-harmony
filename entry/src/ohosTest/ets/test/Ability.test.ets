import { describe, expect, it } from '@ohos/hypium';
import { Driver, ON } from '@kit.UiTestKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

export default function abilityTest() {
  describe('DSHHarmonySmoke', () => {
    it('launch_show_home_title', 0, async (done: Function) => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const bundleName = abilityDelegatorRegistry.getArguments().bundleName;
      const want: Want = {
        bundleName: bundleName,
        abilityName: 'EntryAbility'
      };
      await delegator.startAbility(want);
      const driver = Driver.create();
      await driver.delayMs(1500);
      const comp = await driver.findComponent(ON.text('DSH Harmony'));
      expect(comp != null).assertTrue();
      done();
    });
  });
}
