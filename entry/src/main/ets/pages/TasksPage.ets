import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { AppPrefs } from '../common/store/AppPrefs';
import { PocketApi, TaskInfo } from '../common/utils/PocketApi';
import { CardSync } from '../common/store/CardSync';
import { WindowBar } from '../common/utils/WindowBar';
import { BackButton } from '../components/BackButton';
import { UrlUtils } from '../common/utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 任务/会话管理面板（P1）：
 * 列出电脑端 dsh-pocket 的所有会话（状态/阶段/轮步/时间），自动刷新；
 * 点某项打开对应工作台。
 */
@Entry
@Component
struct TasksPage {
  @State tasks: TaskInfo[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State statusBarH: number = 28;
  private timer: number = -1;
  private baseUrl: string = '';
  private store: ConnectionStore = new ConnectionStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    this.reload();
    if (this.timer < 0) {
      this.timer = setInterval(() => {
        this.reload();
      }, 6000);
    }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const list = await this.store.loadAll(ctx);
    if (list.length === 0) {
      this.tasks = [];
      this.error = '还没有连接记录，先扫码/输入电脑端地址';
      this.loading = false;
      return;
    }
    this.baseUrl = list[0].url;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.listSessions(list[0].url, pin);
    if (r.tasks.length === 0 && r.error.length > 0) {
      this.error = r.error;
    } else {
      this.error = '';
    }
    this.tasks = r.tasks;
    this.loading = false;
  }

  private openTask(url: string): void {
    const normalized = UrlUtils.normalize(url);
    if (normalized === null) {
      return;
    }
    router.pushUrl({ url: 'pages/WebShell', params: { 'url': normalized } });
  }

  @Builder
  Header() {
    Row({ space: 12 }) {
      BackButton()
      Column({ space: 2 }) {
        Text('任务')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text('电脑端会话 · 状态与进度')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  TaskCard(t: TaskInfo) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Circle()
          .width(8)
          .height(8)
          .fill(this.statusColor(t))
        Text(t.title.length > 0 ? t.title : '（未命名会话）')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(this.statusLabel(t))
          .fontSize(11)
          .fontColor('#FFFFFF')
          .backgroundColor(this.statusColor(t))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
        Text(t.turns + ' 轮 · ' + t.steps + ' 步')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Text(CardSync.relativeLabel(t.updatedAt))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      if (t.objective.length > 0) {
        Text(t.objective)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
      }

      Row({ space: 8 }) {
        if (t.running) {
          this.CtrlButton('⏸ 暂停', '#E5484D', () => { this.confirmControl(t, 'goal.pause', '暂停'); })
          this.CtrlButton('⏹ 停止', '#E5484D', () => { this.confirmControl(t, 'session.cancel', '停止'); })
        } else if (t.phase === 'paused') {
          this.CtrlButton('▶ 继续', '#4E6EF2', () => { this.confirmControl(t, 'goal.resume', '继续'); })
        } else if (t.phase !== 'complete') {
          this.CtrlButton('▶ 继续', '#4E6EF2', () => { this.confirmControl(t, 'goal.resume', '继续'); })
          this.CtrlButton('✓ 完成', '#34C759', () => { this.confirmControl(t, 'goal.complete', '完成'); })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_corner_radius'))
    .onClick(() => {
      this.openTask(this.baseUrl);
    })
  }

  @Builder
  Empty() {
    Column({ space: 8 }) {
      Text('还没有会话数据')
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      Text(this.error.length > 0 ? this.error : '在电脑端跑一个任务后，这里会显示进度')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
  }

  @Builder
  CtrlButton(label: string, color: string, action: () => void) {
    Button(label)
      .height(30)
      .fontSize(13)
      .fontColor('#FFFFFF')
      .backgroundColor(color)
      .onClick(() => {
        action();
      })
  }

  private confirmControl(t: TaskInfo, method: string, label: string): void {
    promptAction.showDialog({
      title: label,
      message: '确定要' + label + '「' + (t.title.length > 0 ? t.title : '该会话') + '」吗？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确定', color: '#E5484D' }
      ]
    }).then((res) => {
      if (res.index === 1) {
        this.control(t, method, label);
      }
    }).catch(() => {
    });
  }

  private async control(t: TaskInfo, method: string, label: string): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.controlSession(this.baseUrl, pin, method, t.sessionId);
    if (r.ok) {
      promptAction.showToast({ message: '已' + label });
      this.reload();
    } else {
      promptAction.showToast({ message: label + '失败: ' + r.error });
    }
  }

  private statusLabel(t: TaskInfo): string {
    if (t.running) return '进行中';
    if (t.phase === 'paused') return '已暂停';
    if (t.phase === 'complete') return '已完成';
    return '已结束';
  }

  private statusColor(t: TaskInfo): string {
    if (t.running) return '#34C759';
    if (t.phase === 'paused') return '#F5A623';
    if (t.phase === 'complete') return '#8E8E93';
    return '#8E8E93';
  }

  build() {
    Column() {
      Column({ space: 16 }) {
        this.Header()
        if (this.loading) {
          Column() {
            LoadingProgress().width(28).height(28)
          }
          .width('100%').height(200).justifyContent(FlexAlign.Center)
        } else if (this.tasks.length === 0) {
          this.Empty()
        } else {
          List({ space: 12 }) {
            ForEach(this.tasks, (t: TaskInfo) => {
              ListItem() {
                this.TaskCard(t)
              }
            }, (t: TaskInfo) => t.sessionId)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
        }
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
}
