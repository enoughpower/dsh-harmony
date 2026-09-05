import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { router, promptAction } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionProfile } from '../model/ConnectionProfile';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { UrlUtils } from '../common/utils/UrlUtils';
import { CardSync } from '../common/store/CardSync';
import { AppPrefs } from '../common/store/AppPrefs';
import { WindowBar } from '../common/utils/WindowBar';
import { PushToken } from '../common/store/PushToken';
import { PocketApi, LatestSessionInfo, SessionQueryResult } from '../common/utils/PocketApi';
import { http, connection } from '@kit.NetworkKit';
import { notificationManager } from '@kit.NotificationKit';
import { WebShellView } from '../components/WebShellView';
import { SettingsView } from '../components/SettingsView';
import { HistoryView } from '../components/HistoryView';
import { DeviceUtils } from '../common/utils/DeviceUtils';
import { FeatureFlags } from '../common/config/FeatureFlags';
import { SessionListTab } from './TasksPage';

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
  @State balanceTotal: string = '';
  @State balanceCurrency: string = '';
  @State balanceProgress: number = 100;
  @State cardScale: number = 1;
  /** 余额展示（滚动动画）与阈值告警 */
  @State balanceStr: string = '0.00';
  @State balanceBelow: boolean = false;
  @State balancePulse: number = 1;
  private balancePrevNum: number = 0;
  private balanceAnimTimer: number = -1;
  /** 状态栏高度（沉浸式时内容顶部留白），onPageShow 实测校正 */
  @State statusBarH: number = 28;
  /** 底部导航条/手势条高度（避让用） */
  @State bottomBarH: number = 0;
  /** 平板+横屏双栏 */
  @State wide: boolean = false;
  /** 左栏是否收起（宽屏） */
  @State collapsed: boolean = false;
  /** 底部双 Tab 当前索引（0=首页,1=会话列表） */
  @State curTab: number = 0;
  private hdsController: HdsTabsController = new HdsTabsController();
  /** 当前 Web 连接地址 */
  @State webUrl: string = '';
  /** 最近一次加载最新会话所用的连接基址（供详情页 API 使用） */
  @State activeBase: string = '';
  /** 解析出的“当前可用”连接地址（自动切换：局域网直连 -> 公网隧道）；共享给控制台页做响应式切换 */
  @StorageLink('activeConnUrl') activeConnUrl: string = '';
  @StorageLink('pendingSessionId') @Watch('onPendingDeepLink') pendingSessionId: string = '';
  @StorageLink('pendingDshUrl') pendingDshUrl: string = '';
  /** 内网直连与公网隧道都不可用（首页常驻提示） */
  @State connFailed: boolean = false;
  /** 左栏导航栈：home / settings / history */
  @State leftStack: string[] = ['home'];
  private pushTimer: number = -1;
  private sessionTimer: number = -1;
  private balanceTimer: number = -1;
  private balanceChecking: boolean = false;
  private balanceTickTimer: number = -1;
  private prevBalanceTotal: string = '';
  private connTimer: number = -1;
  private netConn: connection.NetConnection | null = null;
  private store: ConnectionStore = new ConnectionStore();
  /** 会话内是否已自动连接过（防止 WebShell 返回时重复拉/自动拉回） */
  private autoConnected: boolean = false;
  /** 开关配置是否已读取完成（避免异步竞态导致未读到的默认值参与判定） */
  private autoConnectReady: boolean = false;
  aboutToAppear(): void {
    this.reloadHistory();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.getBool(ctx, AppPrefs.KEY_AUTO_CONNECT, true).then((v: boolean) => {
      this.autoConnectEnabled = v;
      this.autoConnectReady = true;
      // 自动启动控制台由 resolveConnection 完成后触发（此处 activeConnUrl 尚未确定）
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
    if (FeatureFlags.PUSH_ENABLED) {
      this.ensureNotifyPermission();
    }
    this.reloadHistory();
    // 自动切换可用连接（局域网直连 -> 公网隧道），并监听网络变化
    this.setupNetListener();
    this.resolveConnection();
    // 沉浸式系统栏兜底：幂等重设（冷启动/时序问题/去其他页面后回首页都保证正确），并实测状态栏高度
    const barCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.immersive(barCtx).catch(() => {
    });
    // 同步 osThemeIsDark（page-show 时 ResourceManager 必已可靠，供 WebShell 等消费）
    AppStorage.setOrCreate('osThemeIsDark', WindowBar.isDark(barCtx));
    WindowBar.statusBarHeight(barCtx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    WindowBar.bottomBarHeight(barCtx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.bottomBarH = h > 0 ? h : this.bottomBarH;
    });
    // 打开首页时同步服务卡片状态（在线探测）
    const synCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    CardSync.syncAll(synCtx).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'card syncAll failed: %{public}s', e.message);
    });
    // 最新会话卡片（首页展示）
    this.refreshSession();
    // 电脑端推送服务在线状态（立即 + 15s 轮询；上架版关闭）
    if (FeatureFlags.PUSH_ENABLED) {
      this.checkPushStatus();
      if (this.pushTimer < 0) {
        this.pushTimer = setInterval(() => {
          this.checkPushStatus();
        }, 15000);
      }
    }
    // DeepSeek 余额（立即 + 60s 轮询；仅局域网可达 3082 时显示）
    this.checkBalance();
    this.startBalanceCountdown();
    if (this.balanceTimer < 0) {
      this.balanceTimer = setInterval(() => {
        this.checkBalance();
      }, 60000);
    }
    if (this.sessionTimer < 0) {
      this.sessionTimer = setInterval(() => {
        this.refreshSession();
      }, 30000);
    }
    // 服务卡片 / 通知点击：带 sessionId 直达对应会话详情页；否则进"该连接的最新会话"详情页；都拿不到则进首页
    const pendingSid = AppStorage.get<string>('pendingSessionId');
    const pending = AppStorage.get<string>('pendingDshUrl');
    if (pending !== undefined && pending !== null && pending.length > 0) {
      if (pendingSid !== undefined && pendingSid !== null && pendingSid.length > 0) {
        AppStorage.setOrCreate('pendingDshUrl', '');
        AppStorage.setOrCreate('pendingSessionId', '');
        this.openSessionById(pending, pendingSid);
      } else {
        AppStorage.setOrCreate('pendingDshUrl', '');
        this.openCardSessionDetail(pending);
      }
      return;
    }
    AppStorage.setOrCreate('pendingSessionId', '');
    // 自动启动控制台：由 resolveConnection() 在确定可用连接后触发
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
    if (this.balanceTimer >= 0) {
      clearInterval(this.balanceTimer);
      this.balanceTimer = -1;
    }
    if (this.balanceTickTimer >= 0) {
      clearInterval(this.balanceTickTimer);
      this.balanceTickTimer = -1;
    }
    if (this.connTimer >= 0) {
      clearTimeout(this.connTimer);
      this.connTimer = -1;
    }
    // 不在此注销网络监听：控制台页在栈顶时仍需感知网络切换并自动切换连接
  }

  /** 自动启动控制台：使用解析出的可用连接；无可用地址时提示用户添加。 */
  private maybeAutoConnect(): void {
    if (!this.autoConnectReady || !this.autoConnectEnabled || this.autoConnected) {
      return;
    }
    this.autoConnected = true;
    if (this.activeConnUrl.length > 0) {
      // 有可用连接 -> 自动启动控制台
      this.openUrl(this.activeConnUrl);
    } else {
      // 没有可用的地址 -> 提示用户添加
      this.promptAddConnection();
    }
  }

  /** 无可用连接地址时，提示用户去添加（扫码/输入地址）。 */
  private promptAddConnection(): void {
    promptAction.showDialog({
      title: '添加连接',
      message: '没有可用的连接地址，无法启动控制台。请扫码，或在设置中输入电脑端地址。',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '去添加', color: '#4D6BFE' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        if (this.wide) {
          this.pushLeft('settings');
        } else {
          router.pushUrl({ url: 'pages/SettingsPage' });
        }
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
    this.activeConnUrl = url;
    this.connFailed = false;
    this.autoConnected = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const profile = new ConnectionProfile(url, UrlUtils.display(url, 32));
    this.store.upsert(ctx, profile).then(() => {
      hilog.info(DOMAIN, TAG, 'connection saved: %{public}s', url);
      // 同步服务卡片（最近连接）
      CardSync.syncAll(ctx).catch(() => {
        hilog.warn(DOMAIN, TAG, 'card sync failed');
      });
      // 连接建立后立即上报推送 token(重装/首连场景不等冷启动；上架版关闭)
      if (FeatureFlags.PUSH_ENABLED) {
        PushToken.ensureAndReport(ctx).catch(() => {
        });
      }
      // 刷新首页连接卡片(内网IP/公网隧道)，立即反映最新连接地址
      this.reloadHistory();
    }).catch((e: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'save connection failed: %{public}s', e.message);
    });
    // 两套交互：窄屏(手机)跳独立 WebShell 页；宽屏(平板)加载到右侧 Web
    if (this.wide) {
      this.webUrl = url;
    } else {
      router.pushUrl({ url: 'pages/WebShell', params: { 'url': url } });
    }
  }

  /** 左栏导航栈顶 */
  private leftStackTop(): string {
    return this.leftStack.length > 0 ? this.leftStack[this.leftStack.length - 1] : 'home';
  }
  private pushLeft(r: string): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.leftStack = this.leftStack.concat([r]);
    });
  }
  private popLeft(): void {
    if (this.leftStack.length > 1) {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
        this.leftStack = this.leftStack.slice(0, this.leftStack.length - 1);
      });
    }
  }
  private navigateWeb(url: string): void {
    this.webUrl = url;
  }

  /** 左栏路由切换过渡动画：淡入 + 自右 24 平移 */
  private routeTransition(): TransitionEffect {
    return TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ x: 24 }))
      .animation({ duration: 220, curve: Curve.EaseInOut });
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

  /** 查 DeepSeek 余额（电脑端 push-notify :3082/api/balance；仅局域网可达）。 */
  private checkBalance(): void {
    if (this.balanceChecking) {
      return;
    }
    this.balanceChecking = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.loadAll(ctx).then((list: ConnectionProfile[]) => {
      if (list.length === 0) {
        this.balanceChecking = false;
        return;
      }
      const host = this.store.pushHostOf(list);
      if (host.length === 0) {
        this.balanceChecking = false;
        return;
      }
      const req = http.createHttp();
      const options: http.HttpRequestOptions = {
        'method': http.RequestMethod.GET,
        'connectTimeout': 3000,
        'readTimeout': 3000
      };
      req.request('http://' + host + ':3082/api/balance', options).then((resp: http.HttpResponse) => {
        if (resp.responseCode === 200) {
          try {
            const j = JSON.parse(String(resp.result ?? '')) as Record<string, Object>;
            const bal = j['balance'] as Record<string, Object> | undefined;
            const t = bal?.['total'];
            const c = bal?.['currency'];
            if (bal !== undefined) {
              this.balanceTotal = typeof t === 'string' ? t : '';
              this.balanceCurrency = typeof c === 'string' ? c : '';
              // 余额变化 -> 缓存 + 刷新首页卡片 + 重置 5 分钟倒计时 + 缩放动画 + 同步服务卡片
              if (this.balanceTotal.length > 0 && this.balanceTotal !== this.prevBalanceTotal) {
                this.prevBalanceTotal = this.balanceTotal;
                this.balanceProgress = 100;
                this.pulseBalanceCard();
                // 阈值告警（低于通知设置的阈值 -> 红色）+ 金额滚动动画
                const numVal = parseFloat(this.balanceTotal);
                if (!isNaN(numVal)) {
                  AppPrefs.getString(ctx, AppPrefs.KEY_PUSH_BALANCE_THRESHOLD, AppPrefs.DEFAULT_PUSH_BALANCE_THRESHOLD).then((th: string) => {
                    const thNum = parseFloat(th);
                    this.balanceBelow = !isNaN(thNum) && numVal > 0 && numVal < thNum;
                  }).catch(() => {
                  });
                  this.animateBalance(numVal);
                } else {
                  this.balanceStr = this.balanceTotal;
                }
                AppPrefs.setString(ctx, AppPrefs.KEY_BALANCE_TOTAL, this.balanceTotal).catch(() => {
                });
                AppPrefs.setString(ctx, AppPrefs.KEY_BALANCE_CURRENCY, this.balanceCurrency).catch(() => {
                });
                // 直接传内存余额刷新小组件（避免读取缓存竞态）
                CardSync.syncAll(ctx, this.balanceTotal, this.balanceCurrency).catch(() => {
                });
              }
            }
          } catch (e) {
          }
        }
      }).catch(() => {
      }).finally(() => {
        req.destroy();
        this.balanceChecking = false;
      });
    }).catch(() => {
      this.balanceChecking = false;
    });
  }

  /** 余额更新时的卡片轻缩动画。 */
  private pulseBalanceCard(): void {
    try {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
        this.cardScale = 1.05;
      });
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
          this.cardScale = 1;
        });
      }, 240);
    } catch (e) {
    }
  }

  /** 余额数字滚动（ease-out）+ 缩放脉冲，刷新更炫酷。 */
  private animateBalance(newVal: number): void {
    const from = this.balancePrevNum;
    this.balancePrevNum = newVal;
    if (this.balanceAnimTimer >= 0) {
      clearInterval(this.balanceAnimTimer);
      this.balanceAnimTimer = -1;
    }
    const steps = 20;
    let step = 0;
    this.balanceAnimTimer = setInterval(() => {
      step++;
      const ratio = step / steps;
      const eased = 1 - Math.pow(1 - ratio, 3);
      this.balanceStr = (from + (newVal - from) * eased).toFixed(2);
      if (step >= steps) {
        clearInterval(this.balanceAnimTimer);
        this.balanceAnimTimer = -1;
        this.balanceStr = newVal.toFixed(2);
      }
    }, 28);
    try {
      this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
        this.balancePulse = 1.18;
      });
      setTimeout(() => {
        this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
          this.balancePulse = 1;
        });
      }, 180);
    } catch (e) {
    }
  }

  /** 5 分钟倒计时（每次余额变化重置为满格，每秒递减）。 */
  private startBalanceCountdown(): void {
    if (this.balanceTickTimer >= 0) {
      return;
    }
    this.balanceTickTimer = setInterval(() => {
      if (this.balanceProgress > 0) {
        this.balanceProgress = Math.max(0, this.balanceProgress - (100 / 300));
      }
    }, 1000);
  }

  /** 设置网络变化监听：网络切换/断开时自动重新解析可用连接。 */
  private setupNetListener(): void {
    if (this.netConn !== null) {
      return;
    }
    try {
      const nc = connection.createNetConnection();
      this.netConn = nc;
      nc.on('netAvailable', () => {
        this.scheduleResolve();
      });
      nc.on('netLost', () => {
        this.scheduleResolve();
      });
      nc.on('netCapabilitiesChange', () => {
        this.scheduleResolve();
      });
      nc.register((err: BusinessError) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'net register failed: %{public}s', err.message);
        }
      });
    } catch (e) {
      this.netConn = null;
    }
  }

  private teardownNetListener(): void {
    if (this.netConn !== null) {
      try {
        this.netConn.unregister((err: BusinessError) => {
        });
      } catch (e) {
      }
      this.netConn = null;
    }
  }

  /** 防抖重新解析（网络抖动时避免连发探测）。 */
  private scheduleResolve(): void {
    if (this.connTimer >= 0) {
      clearTimeout(this.connTimer);
    }
    this.connTimer = setTimeout(() => {
      this.connTimer = -1;
      this.resolveConnection();
    }, 800);
  }

  /** 自动选择可用连接：优先“局域网 IP 直连”，不可达则用“公网隧道”，都不通则标记失败。 */
  private async resolveConnection(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let list: ConnectionProfile[] = [];
    try {
      list = await this.store.loadAll(ctx);
    } catch (e) {
      return;
    }
    if (list.length === 0) {
      this.activeConnUrl = '';
      this.connFailed = false;
      return;
    }
    // 候选顺序：局域网 IP（最近优先）-> 公网隧道（最近优先），去重
    const candidates: string[] = [];
    for (const p of list) {
      if (UrlUtils.isIpHost(p.url) && candidates.indexOf(p.url) < 0) {
        candidates.push(p.url);
      }
    }
    for (const p of list) {
      if (UrlUtils.isTunnelHost(p.url) && candidates.indexOf(p.url) < 0) {
        candidates.push(p.url);
      }
    }
    for (const url of candidates) {
      const ok = await this.checkReachable(url);
      if (ok) {
        this.activeConnUrl = url;
        this.connFailed = false;
        if (this.wide) {
          // 平板/宽屏：控制台内嵌在右侧，直接切换其地址实现自动重连
          this.webUrl = url;
        }
        this.refreshSession();
        this.reloadHistory();
        this.maybeAutoConnect();
        return;
      }
    }
    this.activeConnUrl = '';
    this.connFailed = true;
    this.refreshSession();
    this.maybeAutoConnect();
  }

  /** 探测一个 dsh-pocket 连接是否可达（GET /api/status，3s 超时；2xx/3xx/4xx 视为可达）。 */
  private checkReachable(url: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const req = http.createHttp();
      const options: http.HttpRequestOptions = {
        'method': http.RequestMethod.GET,
        'connectTimeout': 3000,
        'readTimeout': 3000,
        'expectDataType': http.HttpDataType.STRING
      };
      req.request(url.replace(/\/+$/, '') + '/api/status', options).then((resp: http.HttpResponse) => {
        const code = resp.responseCode ?? 0;
        resolve(code >= 200 && code < 500);
      }).catch(() => {
        resolve(false);
      }).finally(() => {
        req.destroy();
      });
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
      const base = this.activeConnUrl.length > 0 ? this.activeConnUrl : list[0].url;
      this.logDebug(ctx, 'target url=' + base);
      this.activeBase = base;
      AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN).then((pin: string) => {
        this.logDebug(ctx, 'pin=' + pin);
        return PocketApi.latestSession(base, pin);
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

  /** 打开最新会话的详情页。 */
  private openLatestSessionDetail(): void {
    const ls = this.latestSession;
    if (ls === null) {
      promptAction.showToast({ message: '暂无最新会话' });
      return;
    }
    const base = this.activeBase.length > 0 ? this.activeBase : this.webUrl;
    if (base.length === 0) {
      promptAction.showToast({ message: '请先连接电脑端' });
      return;
    }
    router.pushUrl({
      url: 'pages/SessionDetailPage',
      params: {
        'sessionId': ls.sessionId,
        'title': ls.title,
        'objective': ls.objective,
        'phase': ls.phase,
        'running': String(ls.running),
        'turns': String(ls.turns),
        'steps': String(ls.steps),
        'updatedAt': String(ls.updatedAt),
        'url': base
      }
    });
  }

  /** 服务卡片点击：默认进"原生会话详情页"（该连接的最近会话）；拿不到会话则留在首页。 */
  private async openCardSessionDetail(url: string): Promise<void> {
    this.activeConnUrl = url;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
      const q = await PocketApi.latestSession(url, pin);
      const ls = q.info;
      if (ls !== null && ls.sessionId.length > 0) {
        this.activeBase = url;
        router.pushUrl({
          url: 'pages/SessionDetailPage',
          params: {
            'sessionId': ls.sessionId,
            'title': ls.title,
            'objective': ls.objective,
            'phase': ls.phase,
            'running': String(ls.running),
            'turns': String(ls.turns),
            'steps': String(ls.steps),
            'updatedAt': String(ls.updatedAt),
            'url': url
          }
        });
        return;
      }
    } catch (e) {
    }
    // 打不开：留在首页（默认）
  }

  /** AppStorage pending 深链变化（通知/卡片前台点击）-> 直达对应会话详情页。 */
  private onPendingDeepLink(): void {
    const sid = this.pendingSessionId;
    const url = this.pendingDshUrl;
    if (sid.length > 0 && url.length > 0) {
      this.pendingSessionId = '';
      this.pendingDshUrl = '';
      this.openSessionById(url, sid);
    }
  }

  /** 通知/卡片带了具体 sessionId：直接打开该会话的原生详情页（会话数据由详情页自取）。 */
  private openSessionById(url: string, sessionId: string): void {
    this.activeConnUrl = url;
    this.activeBase = url;
    router.pushUrl({
      url: 'pages/SessionDetailPage',
      params: {
        'sessionId': sessionId,
        'title': '',
        'objective': '',
        'phase': '',
        'running': 'false',
        'turns': '0',
        'steps': '0',
        'updatedAt': '0',
        'url': url
      }
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

      Row({ space: 8 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.line_viewfinder'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.button_surface'))
        .stateEffect(false)
        .onClick(() => {
          this.scanAndOpen();
        })
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
          if (this.wide) {
            this.pushLeft('settings');
          } else {
            router.pushUrl({ url: 'pages/SettingsPage' });
          }
        })
      }
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

  /** DeepSeek 余额卡片（大数字 + 5 分钟倒计时环形进度 + 更新缩放动画；仅局域网可达时显示） */
  @Builder
  BalanceCard() {
    if (this.balanceTotal.length > 0) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column({ space: 6 }) {
          Text('DeepSeek 余额')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Row({ space: 4 }) {
            Text('¥' + this.balanceStr)
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.balanceBelow ? '#FF3B30' : $r('app.color.text_primary'))
              .scale({ x: this.balancePulse, y: this.balancePulse })
            if (this.balanceCurrency.length > 0) {
              Text(this.balanceCurrency)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 5 })
            }
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        Progress({ value: this.balanceProgress, total: 100, type: ProgressType.Ring })
          .width(15)
          .height(15)
          .color($r('app.color.primary'))
          .style({ strokeWidth: 2 })
          .margin({ right: 0, top: 0 })
          .animation({ duration: 1000, curve: Curve.Linear })
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius($r('app.float.card_corner_radius'))
      .scale({ x: this.cardScale, y: this.cardScale })
    }
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
        Text('›')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
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
            .fontColor(this.latestSession!.running ? '#34C759' : $r('app.color.text_secondary'))
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
      this.openLatestSessionDetail();
    })
  }

  /** 内网直连与公网隧道都不可用时，首页常驻提示。 */
  @Builder
  ConnFailBanner() {
    Row({ space: 10 }) {
      Text('●')
        .fontSize(12)
        .fontColor('#F5A623')
      Text('无法连接电脑端：内网直连与公网隧道都不可用，请检查网络或电脑端服务')
        .fontSize(13)
        .fontColor('#8A5A00')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button('重试')
        .height(28)
        .fontSize(12)
        .fontColor('#F5A623')
        .backgroundColor('#FFF3E0')
        .onClick(() => {
          this.resolveConnection();
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFF8EC')
    .borderRadius($r('app.float.card_corner_radius'))
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
        this.MainContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      const h = newValue.height as number;
      const nowWide = DeviceUtils.shouldSplit(w, h);
      if (nowWide !== this.wide) {
        this.wide = nowWide;
      }
    })
  }

  @Builder
  WideLayout() {
    Row() {
      Column() {
        this.LeftRouteView()
      }
      .width(this.collapsed ? 0 : 360)
      .height('100%')
      .clip(true)
      .backgroundColor($r('app.color.page_background'))
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
          this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
            this.collapsed = !this.collapsed;
          });
        })
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LeftRouteView() {
    if (this.leftStackTop() === 'settings') {
      Column() {
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
      }
      .width('100%')
      .height('100%')
      .transition(this.routeTransition())
    } else if (this.leftStackTop() === 'history') {
      Column() {
        HistoryView({
          onBack: () => {
            this.popLeft();
          },
          onOpen: (url: string) => {
            this.navigateWeb(url);
          }
        })
      }
      .width('100%')
      .height('100%')
      .transition(this.routeTransition())
    } else {
      Column() {
        this.MainContent()
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 内容层：官方 UI Design Kit 底部页签（HdsTabs：悬浮胶囊 + 模糊光感） */
  @Builder
  MainContent() {
    HdsTabs({ controller: this.hdsController }) {
      TabContent() {
        Column({ space: 16 }) {
          this.Header()

          if (this.connFailed) {
            this.ConnFailBanner()
          }

          if (FeatureFlags.PUSH_ENABLED) {
            this.PushStatusRow()
          }

          this.BalanceCard()

          this.LatestSessionCard()

          Blank()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: 0 })
        .alignItems(HorizontalAlign.Center)
      }
      .tabBar(new BottomTabBarStyle($r('app.media.tab_home'), '首页')
        .labelStyle({
          selectedColor: $r('app.color.primary'),
          unselectedColor: $r('app.color.text_primary')
        })
        .iconStyle({
          selectedColor: $r('app.color.primary'),
          unselectedColor: $r('app.color.text_primary')
        }))

      TabContent() {
        SessionListTab()
      }
      .tabBar(new BottomTabBarStyle($r('app.media.tab_list'), '会话列表')
        .labelStyle({
          selectedColor: $r('app.color.primary'),
          unselectedColor: $r('app.color.text_primary')
        })
        .iconStyle({
          selectedColor: $r('app.color.primary'),
          unselectedColor: $r('app.color.text_primary')
        }))
    }
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barFloatingStyle({
      barBottomMargin: 28,
      gradientMask: { maskColor: '#66F1F3F5', maskHeight: 92 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onChange((idx: number) => {
      this.curTab = idx
    })
    .width('100%')
    .height('100%')
  }
}
