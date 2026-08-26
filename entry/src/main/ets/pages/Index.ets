import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { scanBarcode, scanCore } from '@kit.ScanKit';
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
import { AppPrefs } from '../common/store/AppPrefs';
import { WindowBar } from '../common/utils/WindowBar';
import { PushToken } from '../common/store/PushToken';
import { PocketApi, LatestSessionInfo, SessionQueryResult } from '../common/utils/PocketApi';
import { http } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { WebShellView } from '../components/WebShellView';
import { SettingsView } from './SettingsPage';
import { HistoryView } from './HistoryPage';
import { DeviceUtils } from '../common/utils/DeviceUtils';

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
  @State lanConn: ConnectionProfile | null = null;
  @State tunnelConn: ConnectionProfile | null = null;
  @State busy: boolean = false;
  @State autoConnectEnabled: boolean = true;
  @State latestSession: LatestSessionInfo | null = null;
  @State sessionLoading: boolean = false;
  @State sessionError: string = '';
  @State pushOnline: boolean = false;
  @State pushChecking: boolean = false;
  /** 状态栏高度（沉浸式时内容顶部留白），onPageShow 实测校正 */
  @State statusBarH: number = 28;
  /** 平板+横屏双栏 */
  @State wide: boolean = false;
  /** 左栏是否收起（宽屏） */
  @State collapsed: boolean = false;
  /** 当前 Web 连接地址 */
  @State webUrl: string = '';
  /** 窄屏是否展示 Web（连接后全屏 Web） */
  @State webOpen: boolean = false;
  /** 左栏导航栈：home / settings / history */
  @State leftStack: string[] = ['home'];
  private pushTimer: number = -1;
  private sessionTimer: number = -1;
  private store: ConnectionStore = new ConnectionStore();
  /** 会话内是否已自动连接过（防止 WebShell 返回时重复拉/自动拉回） */
  private autoConnected: boolean = false;
  /** 开关配置是否已读取完成（避免异步竞态导致未读到的默认值参与判定） */
  private autoConnectReady: boolean = false;
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
    AppPrefs.getBool(ctx, AppPrefs.KEY_AUTO_CONNECT, true).then((v: boolean) => {
      this.autoConnectEnabled = v;
      this.autoConnectReady = true;
      // 配置就绪后再判定（onPageShow 可能早于此完成）
      this.maybeAutoConnect();
    });
  }

  /** 新装首启:请求通知权限(推送通知展示前提;重复调用无弹窗副作用) */
  private notifyRequested: boolean = false;

  private async ensureNotifyPermission(): Promise<void> {
    if (this.notifyRequested) {
      return;
    }
    this.notifyRequested = true;
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        hilog.info(DOMAIN, TAG, 'notification already enabled');
        return;
      }
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await notificationManager.requestEnableNotification(ctx);
      hilog.info(DOMAIN, TAG, 'notification permission requested');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'request notification permission failed: %{public}s', (e as Error).message);
    }
  }

  onPageShow(): void {
    // 新装首启请求通知权限(推送链路前置)
    this.ensureNotifyPermission();
    this.reloadHistory();
    // 沉浸式系统栏兜底：幂等重设（冷启动/时序问题/去其他页面后回首页都保证正确），并实测状态栏高度
    const barCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.immersive(barCtx).catch(() => {
    });
    // 同步 osThemeIsDark（page-show 时 ResourceManager 必已可靠，供 WebShell 等消费）
    AppStorage.setOrCreate('osThemeIsDark', WindowBar.isDark(barCtx));
    WindowBar.statusBarHeight(barCtx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    // 打开首页时同步服务卡片状态（在线探测）
    const synCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    CardSync.syncAll(synCtx).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'card syncAll failed: %{public}s', e.message);
    });
    // 最新会话卡片（首页展示）
    this.refreshSession();
    // 电脑端推送服务在线状态（立即 + 15s 轮询）
    this.checkPushStatus();
    if (this.pushTimer < 0) {
      this.pushTimer = setInterval(() => {
        this.checkPushStatus();
      }, 15000);
    }
    if (this.sessionTimer < 0) {
      this.sessionTimer = setInterval(() => {
        this.refreshSession();
      }, 30000);
    }
    // 服务卡片点击直达：消费 pendingDshUrl 并跳转 WebShell
    const pending = AppStorage.get<string>('pendingDshUrl');
    if (pending !== undefined && pending !== null && pending.length > 0) {
      AppStorage.setOrCreate('pendingDshUrl', '');
      this.openUrl(pending);
      return;
    }
    // 进入 App 自动连接最近使用的 IP（开关开启时；会话内一次）
    this.maybeAutoConnect();
  }

  onPageHide(): void {
    if (this.pushTimer >= 0) {
      clearInterval(this.pushTimer);
      this.pushTimer = -1;
    }
    if (this.sessionTimer >= 0) {
      clearInterval(this.sessionTimer);
      this.sessionTimer = -1;
    }
  }

  /** 自动连接判定：开关已读取、开关为开、会话内未连接过、且有历史记录时执行 */
  private maybeAutoConnect(): void {
    if (!this.autoConnectReady || !this.autoConnectEnabled || this.autoConnected) {
      return;
    }
    this.autoConnected = true;
    this.store.loadAll(this.getUIContext().getHostContext() as common.UIAbilityContext).then((list: ConnectionProfile[]) => {
      if (list.length > 0) {
        this.openUrl(list[0].url);
      }
    }).catch(() => {
    });
  }

  private reloadHistory(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadAll(ctx).then((list: ConnectionProfile[]) => {
      this.connections = list;
      this.lanConn = this.pickLanConn(list);
      this.tunnelConn = this.pickTunnelConn(list);
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'load history failed: %{public}s', e.message);
    });
  }

  /** 从未排序连接列表挑最近使用的"内网 IP"直连 */
  private pickLanConn(list: ConnectionProfile[]): ConnectionProfile | null {
    for (const p of list) {
      if (UrlUtils.isIpHost(p.url)) {
        return p;
      }
    }
    return null;
  }

  /** 最近使用的"公网隧道"连接（正则匹配 trycloudflare.com 后缀；子域名随机，不用域名比较） */
  private pickTunnelConn(list: ConnectionProfile[]): ConnectionProfile | null {
    for (const p of list) {
      if (UrlUtils.isTunnelHost(p.url)) {
        return p;
      }
    }
    return null;
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
      // 连接建立后立即上报推送 token(重装/首连场景不等冷启动)
      PushToken.ensureAndReport(ctx).catch(() => {
      });
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save connection failed: %{public}s', e.message);
    });
    // 统一容器：连接后加载到右侧（宽屏）或全屏（窄屏）Web
    this.webUrl = url;
    this.webOpen = true;
  }

  /** 左栏导航栈顶 */
  private leftStackTop(): string {
    return this.leftStack.length > 0 ? this.leftStack[this.leftStack.length - 1] : 'home';
  }
  private pushLeft(r: string): void {
    this.leftStack = this.leftStack.concat([r]);
  }
  private popLeft(): void {
    if (this.leftStack.length > 1) {
      this.leftStack = this.leftStack.slice(0, this.leftStack.length - 1);
    }
  }
  private navigateWeb(url: string): void {
    this.webUrl = url;
    this.webOpen = true;
  }
  private closeWeb(): void {
    this.webOpen = false;
  }

  /** 检查电脑端推送服务在线状态（GET host:3082/api/status，3s 超时） */
  private checkPushStatus(): void {
    if (this.pushChecking) {
      return;
    }
    this.pushChecking = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadAll(ctx).then((list: ConnectionProfile[]) => {
      if (list.length === 0) {
        this.pushOnline = false;
        this.pushChecking = false;
        return;
      }
      const host = this.store.pushHostOf(list);
      if (host.length === 0) {
        this.pushOnline = false;
        this.pushChecking = false;
        return;
      }
      const req = http.createHttp();
      const options: http.HttpRequestOptions = {
        'method': http.RequestMethod.GET,
        'connectTimeout': 3000,
        'readTimeout': 3000
      };
      req.request('http://' + host + ':3082/api/status', options).then((resp: http.HttpResponse) => {
        this.pushOnline = resp.responseCode === 200;
      }).catch(() => {
        this.pushOnline = false;
      }).finally(() => {
        req.destroy();
        this.pushChecking = false;
      });
    }).catch(() => {
      this.pushOnline = false;
      this.pushChecking = false;
    });
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

  /** 扫码：直接起系统扫码页（scanBarcode），识别后直接打开，不再经过 ScanPage。 */
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
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: scanBarcode.ScanOptions = {
        'scanTypes': [scanCore.ScanType.ALL]
      };
      const result = await scanBarcode.startScanForResult(ctx, options);
      const raw = result.originalValue ?? '';
      hilog.info(DOMAIN, TAG, 'scan ok: %{public}s', raw);
      if (raw.length > 0) {
        this.openUrl(raw);
      } else {
        promptAction.showToast({ message: '未识别到内容' });
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'scan cancelled/failed: %{public}s', (e as BusinessError).message);
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
        Text('口袋工作台')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)
        Text('随时连接你电脑上的 AI 工作区')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(22)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.button_surface'))
      .stateEffect(false)
      .onClick(() => {
        this.pushLeft('settings');
      })
    }
    .width('100%')
  }

  /** 电脑端推送服务在线状态 */
  @Builder
  PushStatusRow() {
    Row({ space: 8 }) {
      Circle()
        .width(8)
        .height(8)
        .fill(this.pushOnline ? '#34C759' : '#FF3B30')
      Text(this.pushOnline ? '推送服务在线' : '推送服务离线')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
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
    }
    .width('100%')
  }

  @Builder
  EmptyHistory() {
    Column({ space: 8 }) {
      Text('还没有连接记录')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      Text('在电脑端安装配套插件，设置页出现二维码后扫码即可连接')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  build() {
    // 容器：平板+横屏双栏（左导航 | 右 Web），否则单栏（首页/设置/历史导航；连接后全屏 Web）
    Column() {
      if (this.wide) {
        this.WideLayout()
      } else {
        this.NarrowLayout()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      const h = newValue.height as number;
      const nowWide = DeviceUtils.shouldSplitTabletLandscape(w, h);
      if (nowWide !== this.wide) {
        this.wide = nowWide;
      }
    })
  }

  @Builder
  WideLayout() {
    Row() {
      if (!this.collapsed) {
        Column() {
          this.LeftRouteView()
        }
        .width(360)
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
      }
      Stack({ alignContent: Alignment.Start }) {
        if (this.webUrl !== '') {
          WebShellView({ url: this.webUrl, statusBarH: this.statusBarH })
            .width('100%')
            .height('100%')
        } else {
          Column({ space: 8 }) {
            Text('未连接工作台').fontSize(15).fontColor($r('app.color.text_secondary'))
            Text('在左侧选择或扫码连接').fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        Button() {
          if (this.collapsed) {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          } else {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor($r('app.color.floating_surface'))
        .stateEffect(false)
        .margin({ left: 8 })
        .zIndex(10)
        .onClick(() => {
          this.collapsed = !this.collapsed;
        })
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  NarrowLayout() {
    if (this.webOpen && this.webUrl !== '') {
      Column({ space: 0 }) {
        Row() {
          Button() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.floating_surface'))
          .stateEffect(false)
          .onClick(() => {
            this.closeWeb();
          })
          Text('口袋工作台')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 8 })
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 8, right: 8, top: this.statusBarH })
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.page_background'))
        WebShellView({ url: this.webUrl, statusBarH: 0 })
          .layoutWeight(1)
          .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    } else {
      this.LeftRouteView()
    }
  }

  @Builder
  LeftRouteView() {
    if (this.leftStackTop() === 'settings') {
      SettingsView({
        onBack: () => {
          this.popLeft();
        },
        onOpenHistory: () => {
          this.pushLeft('history');
        },
        onOpenConnection: (url: string) => {
          this.navigateWeb(url);
        }
      })
    } else if (this.leftStackTop() === 'history') {
      HistoryView({
        onBack: () => {
          this.popLeft();
        },
        onOpen: (url: string) => {
          this.navigateWeb(url);
        }
      })
    } else {
      this.MainContent()
    }
  }

  @Builder
  MainContent() {
    Column({ space: 16 }) {
      this.Header()

      this.PushStatusRow()

      this.LatestSessionCard()

      if (this.lanConn !== null) {
        ConnectionCard({
          profile: this.lanConn!,
          deleteEnabled: false,
          tag: '内网 IP',
          onOpen: (url: string) => {
            this.openUrl(url);
          }
        })
      }
      if (this.tunnelConn !== null) {
        ConnectionCard({
          profile: this.tunnelConn!,
          deleteEnabled: false,
          tag: '公网隧道',
          onOpen: (url: string) => {
            this.openUrl(url);
          }
        })
      }
      if (this.lanConn === null && this.tunnelConn === null) {
        this.EmptyHistory()
      }

      Blank()

      this.ActionButtons()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: 20 })
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Center)
  }
}
