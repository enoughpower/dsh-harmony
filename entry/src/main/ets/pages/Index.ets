import { scanBarcode, scanCore } from '@kit.ScanKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionProfile } from '../model/ConnectionProfile';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { UrlUtils } from '../common/utils/UrlUtils';
import { ConnectionCard } from '../components/ConnectionCard';
import { UrlInputDialog } from '../components/UrlInputDialog';
import { CardSync } from '../common/store/CardSync';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 入口页：历史连接 + 扫码/手动输入 + 设置。
 * 交互流：扫码（ScanKit 系统默认界面）→ 校验 URL → 存历史 → 进入 WebShell。
 */
@Entry
@Component
struct Index {
  @State connections: ConnectionProfile[] = [];
  @State busy: boolean = false;
  private store: ConnectionStore = new ConnectionStore();
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: UrlInputDialog({
      onConfirm: (url: string) => {
        this.openUrl(url);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.reloadHistory();
  }

  onPageShow(): void {
    this.reloadHistory();
    // 服务卡片点击直达：消费 pendingDshUrl 并跳转 WebShell
    const pending = AppStorage.get<string>('pendingDshUrl');
    if (pending !== undefined && pending !== null && pending.length > 0) {
      AppStorage.setOrCreate('pendingDshUrl', '');
      this.openUrl(pending);
    }
  }

  private reloadHistory(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadAll(ctx).then((list: ConnectionProfile[]) => {
      this.connections = list;
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'load history failed: %{public}s', e.message);
    });
  }

  /** 校验并打开一个连接：存历史 → 跳 WebShell。 */
  private openUrl(raw: string): void {
    const url = UrlUtils.normalize(raw);
    if (url === null) {
      hilog.warn(DOMAIN, TAG, 'invalid url rejected: %{public}s', raw);
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const profile = new ConnectionProfile(url, UrlUtils.display(url, 32));
    this.store.upsert(ctx, profile).then(() => {
      hilog.info(DOMAIN, TAG, 'connection saved: %{public}s', url);
      // 同步服务卡片（最近连接）
      CardSync.syncAll(ctx).catch(() => {
        hilog.warn(DOMAIN, TAG, 'card sync failed');
      });
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save connection failed: %{public}s', e.message);
    });
    router.pushUrl({ url: 'pages/WebShell', params: { 'url': url } });
  }

  private removeConnection(url: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.remove(ctx, url).then(() => {
      this.reloadHistory();
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'remove failed: %{public}s', e.message);
    });
  }

  /** 扫码（系统默认界面）→ 打开。 */
  private async scanAndOpen(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      if (!await this.ensureCameraPermission()) {
        hilog.warn(DOMAIN, TAG, 'camera permission denied');
        return;
      }
      const options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableAlbum: true
      };
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(ctx, options);
      const raw = result?.originalValue ?? '';
      hilog.info(DOMAIN, TAG, 'scan result: %{public}s', raw);
      if (raw.length > 0) {
        this.openUrl(raw);
      }
    } catch (e) {
      // 用户取消（常见 code 200 / 201）与真失败都走这里，取消不算故障
      const err = e as BusinessError;
      hilog.info(DOMAIN, TAG, 'scan ended: code=%{public}d message=%{public}s', err.code, err.message);
    } finally {
      this.busy = false;
    }
  }

  private ensureCameraPermission(): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const atManager = abilityAccessCtrl.createAtManager();
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      atManager.requestPermissionsFromUser(ctx, ['ohos.permission.CAMERA'] as Permissions[])
        .then((result) => {
          const grants = result.authResults ?? [];
          resolve(grants.length > 0 && grants[0] === 0);
        })
        .catch(() => {
          resolve(false);
        });
    });
  }

  @Builder
  Header() {
    Row() {
      Column({ space: 2 }) {
        Text('DSH Harmony')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)
        Text('DeepSeek Harness 口袋客户端')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('设置')
        .height(32)
        .fontSize(13)
        .backgroundColor('#F0F1F5')
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
    }
    .width('100%')
  }

  @Builder
  ActionButtons() {
    Column({ space: 12 }) {
      Button('扫码连接')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.scanAndOpen();
        })
      Button('手动输入地址')
        .width('100%')
        .height(44)
        .fontSize(15)
        .backgroundColor('#F0F1F5')
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.dialogController.open();
        })
    }
    .width('100%')
  }

  @Builder
  EmptyHistory() {
    Column({ space: 8 }) {
      Text('还没有连接记录')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      Text('在电脑端 DSH 安装 dsh-pocket 插件，设置页出现二维码后扫码即可连接')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  build() {
    Column({ space: 16 }) {
      this.Header()

      List({ space: 12 }) {
        ForEach(this.connections, (item: ConnectionProfile) => {
          ListItem() {
            ConnectionCard({
              profile: item,
              onOpen: (url: string) => {
                this.openUrl(url);
              },
              onRemove: (url: string) => {
                this.removeConnection(url);
              }
            })
          }
        }, (item: ConnectionProfile) => item.url)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      if (this.connections.length === 0) {
        this.EmptyHistory()
      }

      this.ActionButtons()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
