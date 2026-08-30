import { webview } from '@kit.ArkWeb';
import { common, bundleManager } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppPrefs } from '../common/store/AppPrefs';
import { PushToken } from '../common/store/PushToken';
import { BackButton } from '../components/BackButton';
import { LanDiscovery, DiscoveredService } from '../common/utils/LanDiscovery';
import { ConnectionCard } from '../components/ConnectionCard';
import { UrlInputDialog } from '../components/UrlInputDialog';
import { UrlUtils } from '../common/utils/UrlUtils';
import { ConnectionProfile } from '../model/ConnectionProfile';
import { WindowBar } from '../common/utils/WindowBar';

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
  @State autoConnect: boolean = true;
  @State pushEnabled: boolean = true;
  @State pushSessionEnd: boolean = true;
  @State lanPin: string = AppPrefs.DEFAULT_LAN_PIN;
  @State scanning: boolean = false;
  @State discovered: DiscoveredService[] = [];
  /** 状态栏高度（沉浸式内容留白，不挡状态栏） */
  @State statusBarH: number = 28;
  @State bottomBarH: number = 0;
  private store: ConnectionStore = new ConnectionStore();
  private addressDlg: CustomDialogController = new CustomDialogController({
    builder: UrlInputDialog({
      onConfirm: (url: string) => {
        this.connectTo(url);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    this.loadVersion();
    this.loadHistoryCount();
    this.loadAutoConnect();
    this.loadPushSettings();
    this.loadLanPin();
    // 实测状态栏高度（沉浸式由 EntryAbility 全局设置）
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    WindowBar.bottomBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.bottomBarH = h > 0 ? h : this.bottomBarH;
    });
  }

  private loadAutoConnect(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.getBool(ctx, AppPrefs.KEY_AUTO_CONNECT, true).then((v: boolean) => {
      this.autoConnect = v;
    }).catch(() => {
    });
  }

  private scanLan(): void {
    if (this.scanning) {
      return;
    }
    this.scanning = true;
    this.discovered = [];
    LanDiscovery.discover().then((found: DiscoveredService[]) => {
      this.discovered = found;
      this.scanning = false;
      if (found.length === 0) {
        promptAction.showToast({ message: '未发现局域网工作台服务' });
      }
    }).catch(() => {
      this.scanning = false;
      promptAction.showToast({ message: '扫描失败' });
    });
  }

  private connectTo(url: string): void {
    const normalized = UrlUtils.normalize(url);
    if (normalized === null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.store.upsert(ctx, new ConnectionProfile(normalized, UrlUtils.display(normalized, 32))).catch(() => {
    });
    router.pushUrl({ url: 'pages/WebShell', params: { 'url': normalized } });
  }

  private loadLanPin(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN).then((v: string) => {
      this.lanPin = v;
    }).catch(() => {
    });
  }

  private saveLanPin(input: string): void {
    const v = input.trim();
    this.lanPin = v;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.setString(ctx, AppPrefs.KEY_LAN_PIN, v.length > 0 ? v : AppPrefs.DEFAULT_LAN_PIN).catch(() => {
    });
  }

  private toggleAutoConnect(checked: boolean): void {
    this.autoConnect = checked;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.setBool(ctx, AppPrefs.KEY_AUTO_CONNECT, checked).catch(() => {
    });
  }

  private loadPushSettings(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.getBool(ctx, AppPrefs.KEY_PUSH_ENABLED, true).then((v: boolean) => {
      this.pushEnabled = v;
    }).catch(() => {
    });
    AppPrefs.getBool(ctx, AppPrefs.KEY_PUSH_SESSION_END, true).then((v: boolean) => {
      this.pushSessionEnd = v;
    }).catch(() => {
    });
  }

  /** 总开关变化：本地保存 + 同步给电脑端推送器。 */
  private togglePush(checked: boolean): void {
    this.pushEnabled = checked;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.setBool(ctx, AppPrefs.KEY_PUSH_ENABLED, checked).catch(() => {
    });
    PushToken.reportSettings(ctx).catch(() => {
    });
  }

  /** 会话结束提醒开关变化。 */
  private togglePushSessionEnd(checked: boolean): void {
    this.pushSessionEnd = checked;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppPrefs.setBool(ctx, AppPrefs.KEY_PUSH_SESSION_END, checked).catch(() => {
    });
    PushToken.reportSettings(ctx).catch(() => {
    });
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

  private logDebug(context: common.Context, msg: string): void {
    try {
      const path = context.filesDir + '/pocket-debug.log';
      let old = '';
      if (fileIo.accessSync(path)) {
        const rf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE);
        const buf = new ArrayBuffer(16384);
        const n = fileIo.readSync(rf.fd, buf);
        old = n > 0 ? util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf, 0, n)) : '';
        fileIo.closeSync(rf);
      }
      old = old + new Date().toString() + ' ' + msg + '\n';
      if (old.length > 65536) {
        old = old.slice(old.length - 65536);
      }
      const wf = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(wf.fd, old);
      fileIo.closeSync(wf);
    } catch (e) {
    }
  }

  private loadHistoryCount(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.logDebug(ctx, 'history count: start');
    this.store.loadDistinctByIp(ctx).then((list) => {
      this.logDebug(ctx, 'history count: distinct=' + list.length);
      this.historyCount = list.length;
    }).catch((e: BusinessError) => {
      this.logDebug(ctx, 'history count failed: ' + e.message);
      // 兜底：用原始列表（与首页一致）
      this.store.loadAll(ctx).then((raw) => {
        this.historyCount = raw.length;
      }).catch(() => {
        this.historyCount = 0;
      });
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
    // 均为同步 API（WebStorage.deleteAllData / WebCookieManager.clearAllCookiesSync）
    webview.WebStorage.deleteAllData();
    webview.WebCookieManager.clearAllCookiesSync();
    promptAction.showToast({ message: 'Web 缓存与数据已清除' });
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .alignSelf(ItemAlign.Start)
      .padding({ left: 8, right: 8 })
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
    // 背景层：延伸到底部安全区；内容层保持避让
    Column() {
      this.MainContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  MainContent() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        BackButton()
        Text('设置')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')

      Column({ space: 8 }) {
        this.SectionTitle('连接')
        Column({ space: 1 }) {
          Row() {
            Text('连接历史（' + this.historyCount + ' 条）')
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
            router.pushUrl({ url: 'pages/HistoryPage' });
          })
          Row() {
            Text('自动启动控制台')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.autoConnect })
              .selectedColor($r('app.color.primary'))
              .onChange((checked: boolean) => {
                this.toggleAutoConnect(checked);
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
          Row() {
            Text('扫描局域网服务')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            if (this.scanning) {
              LoadingProgress()
                .width(18)
                .height(18)
            } else {
              Text('扫描')
                .fontSize(13)
                .fontColor($r('app.color.primary'))
                .onClick(() => {
                  this.scanLan();
                })
            }
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
          Row() {
            Text('输入电脑端地址')
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
            this.addressDlg.open();
          })
          Row({ space: 12 }) {
            Text('局域网 PIN')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            TextInput({ text: this.lanPin, placeholder: AppPrefs.DEFAULT_LAN_PIN })
              .type(InputType.NUMBER_PASSWORD)
              .maxLength(16)
              .layoutWeight(1)
              .fontSize(15)
              .onChange((v: string) => {
                this.saveLanPin(v);
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .borderRadius($r('app.float.card_corner_radius'))
        .clip(true)
      }

      if (this.discovered.length > 0) {
        Column({ space: 8 }) {
          this.SectionTitle('发现 ' + this.discovered.length + ' 个局域网服务')
          ForEach(this.discovered, (item: DiscoveredService) => {
            ConnectionCard({
              profile: new ConnectionProfile(item.url, item.host),
              onOpen: (url: string) => {
                this.connectTo(url);
              },
              onRemove: () => {
                this.discovered = this.discovered.filter((s: DiscoveredService) => s.url !== item.url);
              }
            })
          }, (item: DiscoveredService) => item.url)
        }
        .width('100%')
      }

      Column({ space: 8 }) {
        this.SectionTitle('通知')
        Column({ space: 1 }) {
          Row() {
            Text('启用推送')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pushEnabled })
              .selectedColor($r('app.color.primary'))
              .onChange((checked: boolean) => {
                this.togglePush(checked);
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
          Row() {
            Text('会话结束提醒')
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.pushSessionEnd })
              .selectedColor($r('app.color.primary'))
              .onChange((checked: boolean) => {
                this.togglePushSessionEnd(checked);
              })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .borderRadius($r('app.float.card_corner_radius'))
        .clip(true)
      }

      Column({ space: 8 }) {
        this.SectionTitle('Web 数据')
        Column({ space: 1 }) {
        this.RowItem('清除缓存与 Cookie（需重新登录电脑端）', () => {
          this.clearWebData();
        })
        }
        .width('100%')
        .borderRadius($r('app.float.card_corner_radius'))
        .clip(true)
      }

      Column({ space: 8 }) {
        this.SectionTitle('关于')
        Column({ space: 4 }) {
          Text('口袋工作台 v' + this.version)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('随身连接你电脑上的 AI 工作区。扫码或输入电脑端地址，手机即可查看会话、' +
            '管理任务并接收完成提醒。')
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
    .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: this.bottomBarH + 28 })
    .backgroundColor($r('app.color.page_background'))
    .alignItems(HorizontalAlign.Center)
  }
}
