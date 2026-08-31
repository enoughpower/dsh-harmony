import { router, promptAction, KeyboardAvoidMode as KbAvoidMode } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ConnectionStore } from '../common/store/ConnectionStore';
import { AppPrefs } from '../common/store/AppPrefs';
import { PocketApi, SessionMessage, PromptContentPart, SessionImage } from '../common/utils/PocketApi';
import { MessageDataSource } from '../common/utils/MessageDataSource';
import { CardSync } from '../common/store/CardSync';
import { WindowBar } from '../common/utils/WindowBar';
import { BackButton } from '../components/BackButton';
import { MarkdownText } from '../components/MarkdownText';
import { UrlUtils } from '../common/utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/** 待发送图片：base64(data, 供发送) + PixelMap(pm, 供预览缩略图) */
class PendingImage {
  uri: string = '';
  mediaType: string = '';
  name: string = '';
  data: string = '';
  pm: image.PixelMap | null = null;
  constructor(uri: string, mediaType: string, name: string, data: string, pm: image.PixelMap) {
    this.uri = uri;
    this.mediaType = mediaType;
    this.name = name;
    this.data = data;
    this.pm = pm;
  }
}

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
  @StorageProp('activeConnUrl') @Watch('onActiveConnChange') activeConnUrl: string = '';
  @State msgCount: number = 0;
  private msgSource: MessageDataSource = new MessageDataSource();
  private msgPms: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  @State loadingMsg: boolean = false;
  @State draft: string = '';
  @State sending: boolean = false;
  @State pendingImages: PendingImage[] = [];
  @State previewW: number = 0;
  @State statusBarH: number = 28;
  private timer: number = -1;
  private refreshTimer: number = -1;
  private ws: webSocket.WebSocket | null = null;
  private muxStreamId: string = '';
  private wsRetry: number = 0;
  private token: string = '';
  private detached: boolean = false;
  private store: ConnectionStore = new ConnectionStore();
  private scroller: Scroller = new Scroller();
  private lastMsgCount: number = 0;
  private lastMsgSig: string = '';
  private loadedOnce: boolean = false;
  @State nearBottom: boolean = true;

  aboutToAppear(): void {
    // 键盘避让改为 RESIZE：键盘弹起时在底部压缩内容、顶部保持让出状态栏，避免整页上移顶到状态栏
    try {
      this.getUIContext().setKeyboardAvoidMode(KbAvoidMode.RESIZE);
    } catch (e) {
    }
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
    // 优先使用“当前可用连接”（局域网直连/公网隧道），网络切换后能自动换到新地址，避免打旧地址
    this.baseUrl = this.activeConnUrl.length > 0 ? this.activeConnUrl : (params?.['url'] ?? '');
    this.loadHistory(true, 'first');
    // 真实时：订阅 events.mux WebSocket；本会话事件 -> 防抖刷新（替代高频轮询）
    this.connectEvents();
    // 兜底轮询：WS 断开/静默时仍能刷新（低频，不引起滚动卡顿）
    if (this.timer < 0) {
      this.timer = setInterval(() => {
        this.refresh();
      }, 12000);
    }
  }

  aboutToDisappear(): void {
    this.detached = true;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.disconnectEvents();
  }

  /** 订阅 dsh-pocket events.mux（WebSocket），仅本会话事件触发防抖刷新（真实时，替代高频轮询）。 */
  private async connectEvents(): Promise<void> {
    if (this.detached || this.baseUrl.length === 0 || this.sessionId.length === 0) {
      return;
    }
    if (this.ws !== null) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const token = await PocketApi.getToken(this.baseUrl, pin);
    if (token.length === 0) {
      return;
    }
    this.token = token;
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
    const wsUrl = proto + host + '/api/remote.mux?token=' + encodeURIComponent(token);
    const cookie = PocketApi.getDshAuthCookie(this.baseUrl);
    const ws = webSocket.createWebSocket();
    this.ws = ws;
    ws.on('open', (err: BusinessError, value: Object) => {
      this.muxStreamId = 'dsh-' + util.generateRandomUUID();
      try {
        const argsRec: Record<string, Object> = {};
        const payloadRec: Record<string, Object> = { 'args': argsRec };
        const openMsg: Record<string, Object> = {
          'type': 'open',
          'streamId': this.muxStreamId,
          'endpoint': '$events',
          'payload': payloadRec
        };
        ws.send(JSON.stringify(openMsg));
      } catch (e) {
      }
      this.wsRetry = 0;
    });
    ws.on('message', (err: BusinessError, data: string | ArrayBuffer) => {
      try {
        // 只对本会话、会改变界面的帧刷新（整条消息/状态投影/轮步变化），过滤流式 chunk 与 tool/* 噪音帧
        if (typeof data === 'string' && this.isRelevantFrame(data)) {
          this.scheduleRefresh();
        }
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
      console.log('[detail] ws error: %{public}s', err.message);
    });
    const header: Record<string, string> = {};
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }
    ws.connect(wsUrl, { 'header': header }, (err: BusinessError) => {
      if (err) {
        console.log('[detail] ws connect err: %{public}s', err.message);
      }
    });
  }

  private disconnectEvents(): void {
    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch (e) {
      }
      this.ws = null;
    }
  }

  /** 判断是否为需要刷新界面的本会话帧（避免对高频 chunk/tool 帧做 JSON.parse）。 */
  private isRelevantFrame(raw: string): boolean {
    if (raw.indexOf(this.sessionId) < 0) {
      return false;
    }
    // $events 逻辑流（/api/remote.mux）：api-session/* 事件、emit/waterfall 帧 → 刷新界面；
    // 保留旧标记（assistant/message、user/message、turn/*、step/*）兼容。
    return raw.indexOf('"emit"') >= 0
      || raw.indexOf('"waterfall"') >= 0
      || raw.indexOf('api-session/') >= 0
      || raw.indexOf('assistant/message') >= 0
      || raw.indexOf('user/message') >= 0
      || raw.indexOf('turn/start') >= 0
      || raw.indexOf('turn/end') >= 0
      || raw.indexOf('step/start') >= 0
      || raw.indexOf('step/end') >= 0;
  }

  /** 防抖刷新（400ms，避免高频事件连刷）。 */
  private scheduleRefresh(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      this.refresh();
    }, 400);
  }

  /** 网络切换：把详情页切到新的可用连接（局域网直连 -> 公网隧道），重连 WS 并刷新。 */
  onActiveConnChange(): void {
    const next = this.activeConnUrl;
    if (next.length > 0 && next !== this.baseUrl) {
      this.baseUrl = next;
      this.disconnectEvents();
      this.connectEvents();
      this.refresh();
    }
  }

  /** 拉取消息中图片的 base64 并解码成 PixelMap（按 attachmentId 缓存），供气泡渲染。 */
  private async ensureMsgPms(list: SessionMessage[]): Promise<void> {
    const ids: string[] = [];
    for (const m of list) {
      for (const img of m.images) {
        if (img.attachmentId.length > 0 && !this.msgPms.has(img.attachmentId) && ids.indexOf(img.attachmentId) < 0) {
          ids.push(img.attachmentId);
        }
      }
    }
    for (const id of ids) {
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
        const r = await PocketApi.fetchSessionAttachment(this.baseUrl, pin, this.sessionId, id);
        if (r.ok && r.data.length > 0) {
          const bytes = new util.Base64Helper().decodeSync(r.data);
          const src = image.createImageSource(bytes.buffer);
          const pm = await src.createPixelMap();
          this.msgPms.set(id, pm);
        }
      } catch (e) {
      }
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

  /** 滚动到指定边缘（延迟到下一帧布局后执行）。 */
  private scrollTo(edge: Edge): void {
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(edge);
      } catch (e) {
      }
    }, 40);
  }

  private async loadHistory(showSpinner: boolean = true, mode: string = 'auto'): Promise<void> {
    if (this.sessionId.length === 0 || this.baseUrl.length === 0) {
      return;
    }
    if (showSpinner) {
      this.loadingMsg = true;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const r = await PocketApi.sessionHistory(this.baseUrl, pin, this.sessionId, 50);
    // 拉取失败（网络切换/旧地址不可达）时保留已有消息，不清空对话
    if (r.error.length === 0) {
    // 生成内容签名：只有消息真正变化才重建列表，避免每次刷新全量重建导致的卡顿
    let sig = '';
    for (const m of r.messages) {
      sig += m.role + '\u0000' + m.text + '\u0001';
    }
    if (sig !== this.lastMsgSig) {
      const grew = r.messages.length > this.lastMsgCount;
      // 先解析消息中的图片像素，再更新列表，保证渲染时有图
      await this.ensureMsgPms(r.messages);
      this.msgSource.update(r.messages);
      this.msgCount = r.messages.length;
      this.lastMsgCount = r.messages.length;
      this.lastMsgSig = sig;
      if (mode === 'send') {
        // 发送后滚到最新（让刚发出的消息可见）
        this.scrollTo(Edge.Bottom);
      } else if (mode === 'first') {
        // 首次进入：滚到底部，定位到最后一条消息
        this.scrollTo(Edge.Bottom);
      } else if (grew && this.loadedOnce && this.nearBottom) {
        // 实时刷新发现新消息，且用户本就停在底部 -> 跟随到底部；读上方时不强拖
        this.scrollTo(Edge.Bottom);
      }
      this.loadedOnce = true;
    }
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
          Text('对话')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          if (this.loadingMsg) {
            LoadingProgress().width(16).height(16)
          }
        }
        .width('100%')

        if (this.msgCount === 0) {
          Column() {
            Text('暂无消息').fontSize(13).fontColor($r('app.color.text_secondary'))
          }
          .width('100%').height(120).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10, scroller: this.scroller }) {
            LazyForEach(this.msgSource, (m: SessionMessage, i: number) => {
              ListItem() {
                Column({ space: 4 }) {
                  Text(m.role === 'assistant' ? 'AI' : '我')
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .backgroundColor(m.role === 'assistant' ? '#4E6EF2' : '#8E8E93')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .alignSelf(ItemAlign.Start)
                  MarkdownText({ text: m.text })
                    .width('100%')
                  if (m.images.length > 0) {
                    Row({ space: 8 }) {
                      ForEach(m.images, (img: SessionImage) => {
                        if (this.msgPms.get(img.attachmentId) !== undefined) {
                          Image(this.msgPms.get(img.attachmentId)!)
                            .width(140)
                            .height(140)
                            .borderRadius(8)
                            .objectFit(ImageFit.Cover)
                        }
                      }, (img: SessionImage) => img.attachmentId)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.Start)
                  }
                }
                .width('100%')
                .padding(12)
                .backgroundColor(m.role === 'assistant' ? $r('app.color.card_background') : $r('app.color.user_bubble_background'))
                .borderRadius($r('app.float.card_corner_radius'))
              }
            }, (m: SessionMessage, i: number) => 'm' + i + '|' + m.role + '|' + m.text.length + m.text.slice(0, 8))
            if (this.running) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(14)
                    .height(14)
                    .color($r('app.color.primary'))
                  Text('思考中…')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(12)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius($r('app.float.card_corner_radius'))
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .onScrollIndex((start: number, end: number) => {
            // 用户是否停在底部（含底部“思考中”提示项）；读上方时停止自动跟随
            this.nearBottom = end >= this.msgCount - 1;
          })
        }

        if (this.pendingImages.length > 0) {
          // 外层控件是 Column(居中)，用满宽 Row + justify start 钉到左侧，避免 Scroll 把缩略图居中
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.pendingImages, (item: PendingImage) => {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(item.pm!)
                    .width(60)
                    .height(60)
                    .borderRadius(8)
                    .objectFit(ImageFit.Cover)
                  Button() {
                    SymbolGlyph($r('sys.symbol.xmark'))
                      .fontSize(13)
                      .fontColor(['#FFFFFF'])
                  }
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .backgroundColor('#CC000000')
                  .stateEffect(false)
                  .margin({ right: 4, top: 4 })
                  .onClick(() => {
                    this.removeImage(item);
                  })
                }
                .width(60)
                .height(60)
              }, (item: PendingImage) => item.uri + item.name)
            }
            .justifyContent(FlexAlign.Start)
            .padding({ left: 4, right: 4 })
            .constraintSize({ minWidth: this.previewW })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .onAreaChange((oldV: Area, newV: Area) => {
            const w = newV.width as number;
            if (w > 0 && w !== this.previewW) {
              this.previewW = w;
            }
          })
        }

        Row({ space: 8 }) {
          Button() {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.button_surface'))
          .stateEffect(false)
          .onClick(() => {
            this.pickImage();
          })
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

  private pickingSeq: boolean = false;

  /** 相册选图（可多张），逐张转 JPEG(80) 后作为待发送图片。 */
  private pickImage(): void {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 9;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(options).then((result: photoAccessHelper.PhotoSelectResult) => {
        const uris = result.photoUris ?? [];
        if (uris.length === 0 || this.pickingSeq) {
          return;
        }
        this.pickingSeq = true;
        this.processUris(uris, 0).finally(() => {
          this.pickingSeq = false;
        });
      }).catch((e: BusinessError) => {
        promptAction.showToast({ message: '选择图片失败' });
      });
    } catch (e) {
      promptAction.showToast({ message: '选择图片失败' });
    }
  }

  private processUris(uris: string[], idx: number): Promise<void> {
    if (idx >= uris.length) {
      return Promise.resolve();
    }
    return this.readAndAddImage(uris[idx]).then(() => {
      return this.processUris(uris, idx + 1);
    });
  }

  /** 读取图片并转 JPEG 编码为 base64 + PixelMap(预览)，加入待发送列表。 */
  private readAndAddImage(uri: string): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      let fp: fileIo.File | null = null;
      try {
        fp = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      } catch (e) {
        promptAction.showToast({ message: '图片打开失败' });
        resolve();
        return;
      }
      try {
        const imgSource = image.createImageSource(fp.fd);
        imgSource.createPixelMap().then((pm: image.PixelMap) => {
          const packer = image.createImagePacker();
          const opts: image.PackingOption = {
            'format': 'image/jpeg',
            'quality': 80
          };
          packer.packing(pm, opts).then((data: ArrayBuffer) => {
            try {
              imgSource.release();
              packer.release();
              fileIo.closeSync(fp);
            } catch (e) {
            }
            const b64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
            const name = '图片-' + (this.pendingImages.length + 1) + '-' + Date.now() + '.jpg';
            const img = new PendingImage(uri, 'image/jpeg', name, b64, pm);
            this.pendingImages = this.pendingImages.concat([img]);
            resolve();
          }).catch((e: BusinessError) => {
            try {
              pm.release();
            } catch (e2) {
            }
            promptAction.showToast({ message: '图片处理失败' });
            resolve();
          });
        }).catch((e: BusinessError) => {
          try {
            fileIo.closeSync(fp);
          } catch (e2) {
          }
          promptAction.showToast({ message: '图片解析失败' });
          resolve();
        });
      } catch (e) {
        try {
          fileIo.closeSync(fp);
        } catch (e2) {
        }
        promptAction.showToast({ message: '图片读取失败' });
        resolve();
      }
    });
  }

  /** 移除一张待发送图片并释放其 PixelMap。 */
  private removeImage(item: PendingImage): void {
    this.pendingImages = this.pendingImages.filter((x: PendingImage) => x !== item);
    try {
      item.pm?.release();
    } catch (e) {
    }
  }

  private async sendPrompt(): Promise<void> {
    const text = this.draft.trim();
    const hasImage = this.pendingImages.length > 0;
    if (this.sending || (text.length === 0 && !hasImage)) {
      return;
    }
    this.sending = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pin = await AppPrefs.getString(ctx, AppPrefs.KEY_LAN_PIN, AppPrefs.DEFAULT_LAN_PIN);
    const content: PromptContentPart[] = [];
    if (text.length > 0) {
      const tp: PromptContentPart = { 'type': 'text', 'text': text };
      content.push(tp);
    }
    for (const img of this.pendingImages) {
      if (img.data.length > 0) {
        const ip: PromptContentPart = { 'type': 'image', 'mediaType': img.mediaType, 'data': img.data, 'name': img.name };
        content.push(ip);
      }
    }
    const r = await PocketApi.promptSession(this.baseUrl, pin, this.sessionId, content);
    this.sending = false;
    if (r.ok) {
      this.draft = '';
      for (const img of this.pendingImages) {
        try {
          img.pm?.release();
        } catch (e) {
        }
      }
      this.pendingImages = [];
      this.loadHistory(true, 'send');
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
