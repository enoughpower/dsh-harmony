import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { ConnectionProfile } from '../model/ConnectionProfile';
import { CardSync } from '../common/store/CardSync';
import { LanDiscovery } from '../common/utils/LanDiscovery';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 服务卡片（FormExtensionAbility）：显示最近连接，点击直达 WebShell。
 */
export default class EntryFormAbility extends FormExtensionAbility {
  private store: ConnectionStore = new ConnectionStore();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = String(want.parameters?.['ohos.extra.param.key.form_identity'] ?? '');
    if (formId.length > 0) {
      CardSync.saveFormId(this.context, formId).catch(() => {
        hilog.warn(DOMAIN, TAG, 'save formId failed: %{public}s', formId);
      });
    }
    this.refresh(formId);
    return formBindingData.createFormBindingData(CardSync.defaultData());
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onRemoveForm(formId: string): void {
    CardSync.removeFormId(this.context, formId).catch(() => {
      hilog.warn(DOMAIN, TAG, 'remove formId failed: %{public}s', formId);
    });
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent: %{public}s', message);
  }

  private refresh(formId: string): void {
    this.store.loadAll(this.context).then(async (list: ConnectionProfile[]) => {
      let online = false;
      let known = true;
      if (list.length > 0) {
        try {
          online = await LanDiscovery.isOnline(list[0].url, 1500);
        } catch (e) {
          known = false;
        }
      }
      const fd = formBindingData.createFormBindingData(CardSync.dataFrom(list, online, known));
      if (formId.length > 0) {
        formProvider.updateForm(formId, fd).catch((e: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', formId, e.message);
        });
      }
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'load connections failed: %{public}s', e.message);
    });
  }
}
