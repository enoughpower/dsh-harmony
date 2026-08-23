import { scanBarcode, scanCore } from '@kit.ScanKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
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
import { PocketApi, LatestSessionInfo, SessionQueryResult } from '../common/utils/PocketApi';

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
  @State latestSession: LatestSessionInfo | null = null;
  @State sessionLoading: boolean = false;
  @State sessionError: string = '';
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
    // 最新会话卡片（首页展示）
    this.refreshSession();
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

  /** 拉取最新会话（首页展示；LAN PIN 登录 + session.list） */
  /** 追加调试日志到沙箱文件（pocket-debug.log，hdc 可读） */
  private logDebug(context: common.Context, msg: string): void {
    try {
      const path = context.filesDir + '/pocket-debug.log';
      let content = '';
      if (fileIo.accessSync(path)) {
        const rf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE);
        const buf = new ArrayBuffer(8192);
        const n = fileIo.readSync(rf.fd, buf);
        content = n > 0 ? util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n)) : '';
        fileIo.closeSync(rf);
      }
      content = content + new Date().toString() + ' ' + msg + '\n';
      // 保留最近 64KB
      if (content.length > 65536) {
        content = content.slice(content.length - 65536);
      }
      const wf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(wf.fd, content);
      fileIo.closeSync(wf);
    } catch (e) {
    }
  }

  private refreshSession(): void {
    if (this.sessionLoading) {
      return;
    }
    this.sessionLoading = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.logDebug(ctx, 'refreshSession start');
    this.store.loadAll(ctx).then((list: ConnectionProfile[]) => {
      this.logDebug(ctx, 'history count=' + list.length);
      if (list.length === 0) {
        this.sessionLoading = false;
        this.latestSession = null;
        this.sessionError = '';
        this.logDebug(ctx, 'no history, skip');
        return;
      }
      this.logDebug(ctx, 'target url=' + list[0].url);
      AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN).then((pin: string) => {
        this.logDebug(ctx, 'pin=' + pin);
        return PocketApi.latestSession(list[0].url, pin);
      }).catch(() => {
        const fb: SessionQueryResult = { info: null, error: 'PocketApi 异常', token: '' };
        return fb;
      }).then((query: SessionQueryResult) => {
        this.logDebug(ctx, 'result info=' + (query.info !== null ? query.info.title : 'null') + ' error=' + query.error);
        this.latestSession = query.info;
        this.sessionError = query.error;
        this.sessionLoading = false;
        // 保存令牌供服务卡片复用
        if (query.token.length > 0) {
          AppPrefs.setString(ctx, AppPrefs.KEY_POCKET_TOKEN, query.token).catch(() => {
          });
        }
      });
    }).catch((e: BusinessError) => {
      this.logDebug(ctx, 'loadAll failed: ' + e.message);
      this.sessionLoading = false;
    });
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
  LatestSessionCard() {
    Column({ space: 10 }) {
      Row() {
        Text('最新会话')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.sessionLoading) {
          LoadingProgress()
            .width(16)
            .height(16)
        } else {
          Text('刷新')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.refreshSession();
            })
        }
      }
      .width('100%')

      if (this.latestSession !== null) {
        Text(this.latestSession!.title.length > 0 ? this.latestSession!.title : '（未命名会话）')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
        Row({ space: 10 }) {
          Text(this.latestSession!.running ? '● 进行中' : '● 已结束')
            .fontSize(12)
            .fontColor(this.latestSession!.running ? $r('app.color.primary') : $r('app.color.text_secondary'))
          Text(this.latestSession!.turns + ' 轮 · ' + this.latestSession!.steps + ' 步')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(CardSync.relativeLabel(this.latestSession!.updatedAt))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignSelf(ItemAlign.Start)
      } else {
        Text(this.sessionLoading ? '正在获取…' : '未获取到会话数据')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
        if (this.sessionError.length > 0 && !this.sessionLoading) {
          Text(this.sessionError)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .alignSelf(ItemAlign.Start)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_corner_radius'))
    .onClick(() => {
      if (!this.sessionLoading) {
        this.refreshSession();
      }
    })
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

      this.LatestSessionCard()

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
