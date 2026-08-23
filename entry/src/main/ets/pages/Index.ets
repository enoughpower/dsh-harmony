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
import { LanDiscovery, DiscoveredService } from '../common/utils/LanDiscovery';
import { AppPrefs } from '../common/store/AppPrefs';
import { WindowBar } from '../common/utils/WindowBar';

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
  @State scanning: boolean = false;
  @State discovered: DiscoveredService[] = [];
  @State autoScanEnabled: boolean = true;
  private store: ConnectionStore = new ConnectionStore();
  /** 会话内是否已自动扫描过（防止 WebShell 返回时重复扫/自动拉回） */
  private autoScanned: boolean = false;
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
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.getBool(ctx, AppPrefs.KEY_AUTO_DISCOVER, true).then((v: boolean) => {
      this.autoScanEnabled = v;
    });
  }

  onPageShow(): void {
    this.reloadHistory();
    // 恢复系统栏颜色（WebShell 会把系统栏设为网页色，回到首页需还原）
    const barCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const page = WindowBar.pageBackground(barCtx);
    WindowBar.set(barCtx, page.bg, page.fg);
    // 打开首页时同步服务卡片状态（在线探测）
    const synCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    CardSync.syncAll(synCtx).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'card syncAll failed: %{public}s', e.message);
    });
    // 服务卡片点击直达：消费 pendingDshUrl 并跳转 WebShell
    const pending = AppStorage.get<string>('pendingDshUrl');
    if (pending !== undefined && pending !== null && pending.length > 0) {
      AppStorage.setOrCreate('pendingDshUrl', '');
      this.openUrl(pending);
      return;
    }
    // 打开即自动扫描（app 启动/首次进入时一次；返回首页不重复扫）
    if (this.autoScanEnabled && !this.autoScanned) {
      this.autoScanned = true;
      this.discoverAndOpen();
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

  /** 自动发现局域网 dsh-pocket 服务：单个直接连，多个列出选择 */
  private async discoverAndOpen(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    this.discovered = [];
    try {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 100);
      });
      const found = await LanDiscovery.discover();
      if (found.length === 0) {
        this.scanning = false;
        return;
      }
      if (found.length === 1) {
        this.scanning = false;
        this.openUrl(found[0].url);
        return;
      }
      this.discovered = found;
      this.scanning = false;
    } catch (e) {
      this.scanning = false;
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'discover failed: %{public}s', err.message);
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
        .backgroundColor($r('app.color.button_surface'))
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
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.dialogController.open();
        })
      Button('自动发现局域网 DSH（免扫码）')
        .width('100%')
        .height(44)
        .fontSize(15)
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .enabled(!this.scanning)
        .onClick(() => {
          this.discoverAndOpen();
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
    // 背景层：延伸到底部安全区（手势条区域与页面背景融合），内容层保持安全区内避让
    Column() {
      this.MainContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  MainContent() {
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

      if (this.scanning) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在扫描局域网 3081 端口…')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding({ top: 24, bottom: 8 })
      }

      if (this.discovered.length > 0) {
        Column({ space: 10 }) {
          Text('发现 ' + this.discovered.length + ' 个局域网 DSH 服务')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .alignSelf(ItemAlign.Start)
          ForEach(this.discovered, (item: DiscoveredService) => {
            ConnectionCard({
              profile: new ConnectionProfile(item.url, item.host),
              onOpen: (url: string) => {
                this.openUrl(url);
              },
              onRemove: () => {
                this.discovered = this.discovered.filter((s: DiscoveredService) => s.url !== item.url);
              }
            })
          }, (item: DiscoveredService) => item.url)
        }
        .width('100%')
      }

      if (this.connections.length === 0) {
        this.EmptyHistory()
      }

      this.ActionButtons()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Center)
  }
}
