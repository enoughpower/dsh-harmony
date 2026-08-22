import { webview } from '@kit.ArkWeb';
import { common, bundleManager } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConstants } from '../common/constants/AppConstants';
import { ConnectionStore } from '../common/store/ConnectionStore';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 设置页：连接历史管理、Web 数据清理、关于信息。
 */
@Entry
@Component
struct SettingsPage {
  @State version: string = '1.0.0';
  @State historyCount: number = 0;
  private store: ConnectionStore = new ConnectionStore();

  aboutToAppear(): void {
    this.loadVersion();
    this.loadHistoryCount();
  }

  private loadVersion(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.version = info.versionName;
      })
      .catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'get bundle info failed: %{public}s', e.message);
      });
  }

  private loadHistoryCount(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadAll(ctx).then((list) => {
      this.historyCount = list.length;
    }).catch(() => {
      this.historyCount = 0;
    });
  }

  private clearHistory(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.clear(ctx).then(() => {
      this.historyCount = 0;
      promptAction.showToast({ message: '连接历史已清空' });
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'clear history failed: %{public}s', e.message);
    });
  }

  private clearWebData(): void {
    webview.WebStorage.deleteAllData().then(() => {
      promptAction.showToast({ message: 'Web 缓存与数据已清除' });
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'clear web data failed: %{public}s', e.message);
    });
    webview.WebCookieManager.getInstance().clearAllCookies();
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  RowItem(label: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      action();
    })
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Column({ space: 1 }) {
        this.SectionTitle('连接')
        this.RowItem('连接历史（' + this.historyCount + ' 条）', () => {
          this.clearHistory();
        })
      }
      .width('100%')
      .borderRadius($r('app.float.card_corner_radius'))
      .clip(true)

      Column({ space: 1 }) {
        this.SectionTitle('Web 数据')
        this.RowItem('清除缓存与 Cookie（重新登录 dsh-pocket）', () => {
          this.clearWebData();
        })
      }
      .width('100%')
      .borderRadius($r('app.float.card_corner_radius'))
      .clip(true)

      Column({ space: 8 }) {
        this.SectionTitle('关于')
        Column({ space: 4 }) {
          Text('DSH Harmony v' + this.version)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('DeepSeek Harness 原生客户端，配合 dsh-pocket 插件使用。' +
            '扫码或手动输入 dsh-pocket 设置页的地址，即可在手机上使用电脑上的 DSH。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Start)
            .lineHeight(20)
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.card_corner_radius'))
      }
      .width('100%')

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.page_background'))
  }
}
