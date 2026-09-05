import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { AppPrefs } from '../common/store/AppPrefs';
import { PocketApi, TaskInfo, SearchResult } from '../common/utils/PocketApi';
import { CardSync } from '../common/store/CardSync';
import { WindowBar } from '../common/utils/WindowBar';
import { UrlUtils } from '../common/utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/** 按工作区（cwd）分组的会话组 */
interface WorkspaceGroup {
  name: string;
  cwd: string;
  tasks: TaskInfo[];
}

/**
 * 任务/会话管理面板（P1）：
 * 列出电脑端 dsh-pocket 的所有会话（状态/阶段/轮步/时间），自动刷新；
 * 点某项打开对应工作台。
 */
@Component
export struct SessionListTab {
  @State tasks: TaskInfo[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State statusBarH: number = 28;
  @State bottomBarH: number = 0;
  private timer: number = -1;
  private baseUrl: string = '';
  private token: string = '';
  private ws: webSocket.WebSocket | null = null;
  private wsRetry: number = 0;
  private refreshTimer: number = -1;
  private searchTimer: number = -1;
  @State query: string = '';
  @State searchResults: SearchResult[] = [];
  @State searching: boolean = false;
  @State searchError: string = '';
  @State refreshing: boolean = false;
  @State filter: string = 'all';
  @State filteredTasks: TaskInfo[] = [];
  @State workspaceGroups: WorkspaceGroup[] = [];
  /** 刷新序号：每次取数后自增，用于强制 ForEach 重建（ArkUI ForEach 同 key 不更新） */
  @State refreshSeq: number = 0;
  private store: ConnectionStore = new ConnectionStore();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
    WindowBar.bottomBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.bottomBarH = h > 0 ? h : this.bottomBarH;
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
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch (e) {
      }
      this.ws = null;
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
    this.applyFilter();
    this.refreshSeq++;
    this.token = r.token;
    this.loading = false;
    if (this.token.length > 0) {
      this.connectEvents();
    }
  }

  /** 订阅 dsh-pocket events.mux（WebSocket），任何会话事件 → 防抖刷新列表（真实时） */
  private connectEvents(): void {
    if (this.baseUrl.length === 0 || this.token.length === 0) {
      return;
    }
    if (this.ws !== null) {
      return;
    }
    let rest = this.baseUrl;
    let proto = 'ws://';
    if (rest.startsWith('http://')) {
      rest = rest.substring(7);
    } else if (rest.startsWith('https://')) {
      proto = 'wss://';
      rest = rest.substring(8);
    } else {
      return;
    }
    const host = rest.split('/')[0];
    const wsUrl = proto + host + '/api/events.mux?token=' + encodeURIComponent(this.token);
    const ws = webSocket.createWebSocket();
    this.ws = ws;
    ws.on('open', (err: BusinessError, value: Object) => {
      console.log('[task] events connected');
      this.wsRetry = 0;
    });
    ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      try {
        // 任何会话事件都值得刷新一次（防抖 500ms，避免高频事件连刷）
        this.scheduleRefresh();
      } catch (e) {
      }
    });
    ws.on('close', (err: BusinessError, value: Object) => {
      this.ws = null;
      this.scheduleRefresh();
      if (this.wsRetry < 3) {
        this.wsRetry++;
        setTimeout(() => {
          this.connectEvents();
        }, 5000 * this.wsRetry);
      }
    });
    ws.on('error', (err: BusinessError) => {
      console.log('[task] ws error: %{public}s', err.message);
    });
    ws.connect(wsUrl, (err: BusinessError) => {
      if (err) {
        console.log('[task] ws connect err: %{public}s', err.message);
      }
    });
  }

  /** 防抖刷新 */
  private scheduleRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      this.reload();
    }, 500);
  }

  private openDetailFor(sessionId: string): void {
    for (const t of this.tasks) {
      if (t.sessionId === sessionId) {
        this.openDetail(t);
        return;
      }
    }
    // 搜索结果可能不在当前列表(归档等)，回退到工作台
    this.openTask(this.baseUrl);
  }

  private openDetail(t: TaskInfo): void {
    router.pushUrl({
      url: 'pages/SessionDetailPage',
      params: {
        'sessionId': t.sessionId,
        'title': t.title,
        'objective': t.objective,
        'phase': t.phase,
        'running': String(t.running),
        'turns': String(t.turns),
        'steps': String(t.steps),
        'updatedAt': String(t.updatedAt),
        'url': this.baseUrl
      }
    });
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
    Row() {
      Column({ space: 2 }) {
        Text('会话列表')
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

  /** 工作区分组标题 */
  @Builder
  WorkspaceHeader(g: WorkspaceGroup) {
    Row({ space: 8 }) {
      Circle()
        .width(6)
        .height(6)
        .fill($r('app.color.primary'))
      Text(g.name)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(String(g.tasks.length))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.card_background'))
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(10)
      Blank()
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 8 })
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

    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_corner_radius'))
    .onClick(() => {
      this.openDetailFor(t.sessionId);
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

  private filterTasks(list: TaskInfo[]): TaskInfo[] {
    if (this.filter === 'running') {
      return list.filter((t: TaskInfo) => t.running);
    }
    if (this.filter === 'paused') {
      return list.filter((t: TaskInfo) => t.phase === 'paused');
    }
    if (this.filter === 'complete') {
      return list.filter((t: TaskInfo) => t.phase === 'complete');
    }
    return list;
  }

  private applyFilter(): void {
    this.filteredTasks = this.filterTasks(this.tasks);
    this.computeGroups();
  }

  /** 按工作区（cwd）分组：组序按最新会话时间，组内会话时间倒序。 */
  private computeGroups(): void {
    const groups: WorkspaceGroup[] = [];
    for (const t of this.filteredTasks) {
      let g: WorkspaceGroup | null = null;
      for (const gg of groups) {
        if (gg.cwd === t.cwd) {
          g = gg;
          break;
        }
      }
      if (g === null) {
        g = { name: this.workspaceLabel(t.cwd), cwd: t.cwd, tasks: [] };
        groups.push(g);
      }
      g.tasks.push(t);
    }
    this.workspaceGroups = groups;
  }

  /** 工作区显示名：取目录最后一段。 */
  private workspaceLabel(cwd: string): string {
    if (cwd.length === 0) {
      return '未命名工作区';
    }
    const parts = cwd.split('/').filter((s: string) => s.length > 0);
    return parts.length > 0 ? parts[parts.length - 1] : cwd;
  }

  @Builder
  FilterChip(label: string, key: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.filter === key ? '#FFFFFF' : $r('app.color.text_secondary'))
      .backgroundColor(this.filter === key ? $r('app.color.primary') : $r('app.color.card_background'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .onClick(() => {
        this.filter = key;
        this.applyFilter();
      })
  }

  private doSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.runSearch();
    }, 400);
  }

  private async runSearch(): Promise<void> {
    const q = this.query.trim();
    if (q.length === 0) {
      this.searchResults = [];
      this.searchError = '';
      return;
    }
    this.searching = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.searchSessions(this.baseUrl, pin, q);
    this.searchResults = r.results;
    this.searchError = r.error;
    this.searching = false;
  }

  private onPullRefresh(): void {
    this.refreshing = true;
    this.reload().then(() => {
      this.refreshing = false;
    }).catch(() => {
      this.refreshing = false;
    });
  }

  @Builder
  SearchCard(r: SearchResult) {
    Column({ space: 6 }) {
      if (r.snippet.length > 0) {
        Text(r.snippet)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
      }
      Text('ID: ' + r.sessionId.slice(0, 12))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_corner_radius'))
    .onClick(() => {
      this.openDetailFor(r.sessionId);
    })
  }

  @Builder
  SearchList() {
    if (this.searching) {
      Column() {
        LoadingProgress().width(24).height(24)
      }
      .width('100%').height(160).justifyContent(FlexAlign.Center)
    } else if (this.searchResults.length === 0) {
      Column({ space: 8 }) {
        Text('无匹配会话').fontSize(15).fontColor($r('app.color.text_primary'))
        if (this.searchError.length > 0) {
          Text(this.searchError).fontSize(12).fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        }
      }
      .width('100%').padding({ top: 40 })
    } else {
      List({ space: 12 }) {
        ForEach(this.searchResults, (r: SearchResult) => {
          ListItem() {
            this.SearchCard(r)
          }
        }, (r: SearchResult) => r.sessionId + r.snippet)
      }
      .width('100%').layoutWeight(1).scrollBar(BarState.Off)
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
        TextInput({ text: this.query, placeholder: '搜索会话…' })
          .height(40)
          .fontSize(14)
          .padding({ left: 12, right: 12 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.card_corner_radius'))
          .onChange((v: string) => {
            this.query = v;
            this.doSearch();
          })
        Row({ space: 8 }) {
          this.FilterChip('全部', 'all')
          this.FilterChip('进行中', 'running')
          this.FilterChip('已暂停', 'paused')
          this.FilterChip('已完成', 'complete')
        }
        .width('100%')
        .padding({ left: 4, right: 4 })
        if (this.loading) {
          Column() {
            LoadingProgress().width(28).height(28)
          }
          .width('100%').height(200).justifyContent(FlexAlign.Center)
        } else if (this.query.trim().length > 0) {
          this.SearchList()
        } else if (this.filteredTasks.length === 0) {
          this.Empty()
        } else {
          Refresh({ refreshing: this.refreshing, offset: 40 }) {
            List({ space: 12 }) {
              ForEach(this.workspaceGroups, (g: WorkspaceGroup) => {
                ListItem() {
                  Column({ space: 12 }) {
                    this.WorkspaceHeader(g)
                    ForEach(g.tasks, (t: TaskInfo) => {
                      this.TaskCard(t)
                    }, (t: TaskInfo) => this.refreshSeq + '|' + t.sessionId)
                  }
                  .width('100%')
                }
              }, (g: WorkspaceGroup) => this.refreshSeq + '|' + g.cwd)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .onRefreshing(() => {
            this.onPullRefresh();
          })
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 20, right: 20, top: this.statusBarH + 16, bottom: this.bottomBarH })
      .backgroundColor($r('app.color.page_background'))
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
