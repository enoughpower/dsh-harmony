import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { AppPrefs } from '../common/store/AppPrefs';
import { PocketApi, SessionMessage } from '../common/utils/PocketApi';
import { CardSync } from '../common/store/CardSync';
import { WindowBar } from '../common/utils/WindowBar';
import { BackButton } from '../components/BackButton';
import { UrlUtils } from '../common/utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 会话详情页：展示进度/目标/状态/最新消息，并提供控制操作。
 */
@Entry
@Component
struct SessionDetailPage {
  @State sessionId: string = '';
  @State title: string = '';
  @State objective: string = '';
  @State phase: string = '';
  @State running: boolean = false;
  @State turns: number = 0;
  @State steps: number = 0;
  @State updatedAt: number = 0;
  @State baseUrl: string = '';
  @State messages: SessionMessage[] = [];
  @State loadingMsg: boolean = false;
  @State draft: string = '';
  @State sending: boolean = false;
  @State statusBarH: number = 28;
  private timer: number = -1;
  private store: ConnectionStore = new ConnectionStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    const params = router.getParams() as Record<string, string>;
    this.sessionId = params?.['sessionId'] ?? '';
    this.title = params?.['title'] ?? '';
    this.objective = params?.['objective'] ?? '';
    this.phase = params?.['phase'] ?? '';
    this.running = params?.['running'] === 'true';
    this.turns = parseInt(params?.['turns'] ?? '0', 10);
    this.steps = parseInt(params?.['steps'] ?? '0', 10);
    this.updatedAt = parseInt(params?.['updatedAt'] ?? '0', 10);
    this.baseUrl = params?.['url'] ?? '';
    this.loadHistory();
    if (this.timer < 0) {
      this.timer = setInterval(() => {
        this.refresh();
      }, 3000);
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** 定时刷新：更新会话进度/目标/状态 + 消息，实现近实时 */
  private async refresh(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const t = await PocketApi.getSession(this.baseUrl, pin, this.sessionId);
    if (t !== null) {
      this.title = t.title;
      this.objective = t.objective;
      this.phase = t.phase;
      this.running = t.running;
      this.turns = t.turns;
      this.steps = t.steps;
      this.updatedAt = t.updatedAt;
    }
    this.loadHistory(false);
  }

  private async loadHistory(showSpinner: boolean = true): Promise<void> {
    if (this.sessionId.length === 0 || this.baseUrl.length === 0) {
      return;
    }
    if (showSpinner) {
      this.loadingMsg = true;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.sessionHistory(this.baseUrl, pin, this.sessionId, 12);
    if (r.messages.length > 0) {
      this.messages = r.messages;
    }
    this.loadingMsg = false;
  }

  private openWorkbench(): void {
    const n = UrlUtils.normalize(this.baseUrl);
    if (n !== null) {
      router.pushUrl({ url: 'pages/WebShell', params: { 'url': n } });
    }
  }

  private confirmControl(method: string, label: string): void {
    promptAction.showDialog({
      title: label,
      message: '确定要' + label + '「' + (this.title.length > 0 ? this.title : '该会话') + '」吗？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确定', color: '#E5484D' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        this.control(method, label);
      }
    }).catch(() => {
    });
  }

  private async control(method: string, label: string): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.controlSession(this.baseUrl, pin, method, this.sessionId);
    if (r.ok) {
      promptAction.showToast({ message: '已' + label });
      router.back();
    } else {
      promptAction.showToast({ message: label + '失败: ' + r.error });
    }
  }

  @Builder
  CtrlButton(label: string, color: string, action: () => void) {
    Button(label)
      .height(32)
      .fontSize(13)
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .onClick(() => {
        action();
      })
  }

  @Builder
  Header() {
    Row({ space: 12 }) {
      BackButton()
      Column({ space: 2 }) {
        Text(this.title.length > 0 ? this.title : '会话详情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('会话详情')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        this.Header()

        Row({ space: 8 }) {
          Text(this.statusLabel())
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor(this.statusColor())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(4)
          Text(this.turns + ' 轮 · ' + this.steps + ' 步')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Text(CardSync.relativeLabel(this.updatedAt))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')

        if (this.objective.length > 0) {
          Column({ space: 4 }) {
            Text('目标').fontSize(12).fontColor($r('app.color.text_secondary')).alignSelf(ItemAlign.Start)
            Text(this.objective)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .alignSelf(ItemAlign.Start)
          }
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_corner_radius'))
        }

        Row({ space: 8 }) {
          if (this.running) {
            this.CtrlButton('⏸ 暂停', '#E5484D', () => { this.confirmControl('goal.pause', '暂停'); })
            this.CtrlButton('⏹ 停止', '#E5484D', () => { this.confirmControl('session.cancel', '停止'); })
          } else if (this.phase === 'paused') {
            this.CtrlButton('▶ 继续', '#4E6EF2', () => { this.confirmControl('goal.resume', '继续'); })
          } else if (this.phase !== 'complete') {
            this.CtrlButton('▶ 继续', '#4E6EF2', () => { this.confirmControl('goal.resume', '继续'); })
            this.CtrlButton('✓ 完成', '#34C759', () => { this.confirmControl('goal.complete', '完成'); })
          }
          Blank()
          Button('打开工作台')
            .height(32)
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.button_surface'))
            .onClick(() => {
              this.openWorkbench();
            })
        }
        .width('100%')

        Row() {
          Text('最新消息')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          if (this.loadingMsg) {
            LoadingProgress().width(16).height(16)
          }
        }
        .width('100%')

        if (this.messages.length === 0) {
          Column() {
            Text('暂无消息').fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%').height(120).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.messages, (m: SessionMessage, i: number) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(m.role === 'assistant' ? 'AI' : '我')
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .backgroundColor(m.role === 'assistant' ? '#4E6EF2' : '#8E8E93')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .alignSelf(ItemAlign.Start)
                  Text(m.text)
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(5)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .alignSelf(ItemAlign.Start)
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius($r('app.float.card_corner_radius'))
              }
            }, (m: SessionMessage, i: number) => 'm' + i + m.role + m.text.slice(0, 8))
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }

        Row({ space: 8 }) {
          TextInput({ text: this.draft, placeholder: '给 AI 发消息…' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(20)
            .onChange((v: string) => {
              this.draft = v;
            })
          Button('发送')
            .height(40)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.primary'))
            .enabled(!this.sending)
            .onClick(() => {
              this.sendPrompt();
            })
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: 20 })
      .backgroundColor($r('app.color.page_background'))
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private async sendPrompt(): Promise<void> {
    const text = this.draft.trim();
    if (text.length === 0 || this.sending) {
      return;
    }
    this.sending = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.promptSession(this.baseUrl, pin, this.sessionId, text);
    this.sending = false;
    if (r.ok) {
      this.draft = '';
      this.messages = [];
      this.loadHistory();
      promptAction.showToast({ message: '已发送' });
    } else {
      promptAction.showToast({ message: '发送失败: ' + r.error });
    }
  }

  private statusLabel(): string {
    if (this.running) return '进行中';
    if (this.phase === 'paused') return '已暂停';
    if (this.phase === 'complete') return '已完成';
    return '已结束';
  }

  private statusColor(): string {
    if (this.running) return '#34C759';
    if (this.phase === 'paused') return '#F5A623';
    if (this.phase === 'complete') return '#8E8E93';
    return '#8E8E93';
  }
}
