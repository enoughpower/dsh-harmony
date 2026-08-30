import { webview } from '@kit.ArkWeb';
import { router, promptAction } from '@kit.ArkUI';
import { picker, fileUri, fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/constants/AppConstants';
import { UrlUtils } from '../common/utils/UrlUtils';
import { WindowBar } from '../common/utils/WindowBar';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * WebShell：dsh-pocket 网页的 ArkWeb 套壳页（v1.0 核心）。
 *
 * 布局自适应：
 *  - 窄屏（手机竖屏 / 折叠屏折叠态）：Web 全屏 + 顶部操作条
 *  - 宽屏（折叠屏展开态 / 平板横屏，>= WIDE_BREAKPOINT vp）：左侧连接侧栏 + 右侧 Web
 *
 * 网络说明：dsh-pocket 局域网地址为明文 http://IP:3081，公网为 https 隧道；
 * Web 组件默认放行 http(s)，无需额外网络安全配置。
 */
@Entry
@Component
struct WebShell {
  @State url: string = 'about:blank';
  @State title: string = '口袋工作台';
  @State loading: boolean = true;
  @State progress: number = 0;
  @State failed: boolean = false;
  @State failText: string = '';
  @State wide: boolean = false;
  /** 状态栏高度（沉浸式时进度条下移留白） */
  @State statusBarH: number = 0;
  @StorageLink('osThemeIsDark') @Watch('onThemeChange') osThemeIsDark: boolean = false;
  @StorageLink('activeConnUrl') @Watch('onActiveConnChange') activeConnUrl: string = '';
  /** 网页实际外观：-1 未知（回退系统主题）/ 0 浅色 / 1 深色（网页内可独立于系统切换） */
  @State webDark: number = -1;
  private themeTimer: number = -1;
  private controller: webview.WebviewController = new webview.WebviewController();

  /** 深浅色切换回调：刷新系统栏，与网页主题同步 */
  onThemeChange(): void {
    this.applyWebBar();
  }

  /** 网络切换后，自动把控制台切到新的可用连接（局域网直连 -> 公网隧道）。 */
  onActiveConnChange(): void {
    if (this.url.length === 0 || this.url === 'about:blank') {
      return;
    }
    const norm = UrlUtils.normalize(this.activeConnUrl);
    if (norm !== null && norm !== this.url) {
      this.url = norm;
      this.title = UrlUtils.display(norm, 24);
      this.loading = true;
      this.failed = false;
      this.failText = '';
      hilog.info(DOMAIN, TAG, 'WebShell auto-switch to: %{public}s', norm);
    }
  }

  /** 状态栏底色条：优先网页实际外观（网页内可独立切深浅），未知时回退系统主题 */
  private stripBg(): string {
    if (this.webDark === 1) {
      return '#151517';
    }
    if (this.webDark === 0) {
      return '#FFFFFF';
    }
    return this.osThemeIsDark ? '#151517' : '#FFFFFF';
  }

  /** WebShell 沉浸式（统一）：内容色跟随网页实际主题（网页内可独立于系统切浅/深），并实测状态栏高（网页不挡状态栏） */
  private applyWebBar(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dark = this.webDark >= 0 ? this.webDark === 1 : this.osThemeIsDark;
    WindowBar.immersive(ctx, dark).catch(() => {
    });
    WindowBar.statusBarHeight(ctx, (px: number) => this.getUIContext().px2vp(px)).then((h: number) => {
      this.statusBarH = h > 0 ? h : this.statusBarH;
    });
  }

  /** 轮询网页 body 实际背景亮度 → 判定网页当前外观（不依赖网页主题实现方式；forceDarkAccess 已关，网页自主） */
  private pollWebTheme(): void {
    const js = "(function(){" +
      "function bg(el){var c=getComputedStyle(el).backgroundColor;" +
      "var m=c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);return m?m:null;}" +
      "var m=bg(document.body)||bg(document.documentElement);" +
      "if(!m||m[1]==='0'&&m[2]==='0'&&m[3]==='0'){return -1;}" +
      "var lum=0.299*(+m[1])+0.587*(+m[2])+0.114*(+m[3]);" +
      "return lum<100?1:0;" +
      "})()";
    try {
      this.controller.runJavaScript(js).then((ret: string) => {
        const v = parseInt(ret, 10);
        if (v === 0 || v === 1) {
          if (this.webDark !== v) {
            this.webDark = v;
            this.applyWebBar();
          }
        }
      }).catch(() => {
      });
    } catch (e) {
    }
  }

  aboutToAppear(): void {
    // CDP 调试（webview-devtools 需要；正式版可移除）
    webview.WebviewController.setWebDebuggingAccess(true);
    this.applyWebBar();
    // 网页外观轮询（网页内可独立切主题，需跟随刷新状态栏底色/图标色）
    if (this.themeTimer < 0) {
      this.themeTimer = setInterval(() => {
        this.pollWebTheme();
      }, 1200);
    }
    const params = router.getParams() as Record<string, string>;
    const raw = params?.['url'] ?? '';
    const normalized = UrlUtils.normalize(raw);
    if (normalized !== null) {
      this.url = normalized;
      this.title = UrlUtils.display(normalized, 24);
      hilog.info(DOMAIN, TAG, 'WebShell loading: %{public}s', normalized);
    } else {
      this.failed = true;
      this.failText = '无效的连接地址';
    }
  }

  aboutToDisappear(): void {
    if (this.themeTimer >= 0) {
      clearInterval(this.themeTimer);
      this.themeTimer = -1;
    }
  }

  onPageShow(): void {
    this.applyWebBar();
    this.ensureDownloadUri();
    this.pollWebTheme();
  }

  /** 物理返回键：优先 Web 内后退。 */
  onBackPress(): boolean {
    if (this.controller.accessBackward()) {
      this.controller.backward();
      return true;
    }
    return false;
  }

  private onRetry(): void {
    this.failed = false;
    this.failText = '';
    this.loading = true;
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'retry failed: %{public}s', (e as Error).message);
    }
  }

  private refreshing: boolean = false;

  private onRefresh(): void {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    this.loading = true;
    try {
      this.controller.refresh();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'refresh failed: %{public}s', (e as Error).message);
    }
    setTimeout(() => {
      this.refreshing = false;
    }, 1500);
  }

  private backHome(): void {
    router.back();
  }

  /** 相册选图 → 注入 DSH 输入框（合成 drop 事件，DSH 原生 onDrop 接收为附件） */
  private pickAndInjectImage(): void {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(options).then((result: photoAccessHelper.PhotoSelectResult) => {
        const uris = result.photoUris ?? [];
        if (uris.length === 0) {
          return;
        }
        this.injectImageToWeb(uris[0]);
      }).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'photo pick failed: %{public}s', (e as Error).message);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'photo pick error: %{public}s', (e as Error).message);
    }
  }

  /** 相册图（任意格式）→ ImageKit 转 JPEG(80) → base64 → runJavaScript 构造 File + drop 事件（DSH 单张 ≤20M） */
  private injectImageToWeb(uri: string): void {
    const doInject = (b64: string): void => {
      const name = 'dsh-upload-' + Date.now() + '.jpg';
      // 页面注入：base64 → File → DataTransfer → 合成 drop（DSH 全局 onDrop 接收为附件）
      const js = "(function(){" +
        "try{" +
        "var b64='" + b64 + "';" +
        "var name='" + name + "';" +
        "var bin=atob(b64);" +
        "var bytes=new Uint8Array(bin.length);" +
        "for(var i=0;i<bin.length;i++){bytes[i]=bin.charCodeAt(i);}" +
        "var file=new File([bytes],name,{type:'image/jpeg'});" +
        "var dt=new DataTransfer();" +
        "dt.items.add(file);" +
        "document.dispatchEvent(new DragEvent('drop',{dataTransfer:dt,bubbles:true,cancelable:true}));" +
        "return 'ok';" +
        "}catch(e){return 'err:'+e.message;}" +
        "})()";
      this.controller.runJavaScript(js).then((ret: string) => {
        hilog.info(DOMAIN, TAG, 'inject drop: %{public}s', ret);
      }).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'runJavaScript failed: %{public}s', e.message);
      });
    };

    // media URI 需先以 fd 打开再解码
    let fp: fileIo.File | null = null;
    try {
      fp = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'open media failed: %{public}s', (e as Error).message);
      promptAction.showToast({ message: '图片打开失败' });
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
            pm.release();
            fileIo.closeSync(fp);
          } catch (e) {
          }
          const b64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
          doInject(b64);
        }).catch((e: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'packing failed: %{public}s', e.message);
          promptAction.showToast({ message: '图片处理失败' });
        });
      }).catch((e: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'createPixelMap failed: %{public}s', e.message);
        promptAction.showToast({ message: '图片解析失败' });
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'inject image failed: %{public}s', (e as Error).message);
      try {
        fileIo.closeSync(fp);
      } catch (e2) {
      }
      promptAction.showToast({ message: '图片读取失败' });
    }
  }





  /** 系统下载服务保存：cookie 认证 + 自动保存到系统下载文件夹（下载管理/通知栏可见） */
  private downloading: boolean = false;

  /** DOWNLOAD 模式目录 URI（file://docs/storage/Users/currentUser/Download/<bundleName>/），持久化授权 */
  private downloadUri: string = '';
  private downloadUriPending: boolean = false;

  /** 获取公共下载目录（DOWNLOAD 模式：跳过选择界面、自动创建在 Download/包名/ 目录） */
  private ensureDownloadUri(): void {
    if (this.downloadUri !== '' || this.downloadUriPending) {
      return;
    }
    this.downloadUriPending = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const dp = new picker.DocumentViewPicker(ctx);
      dp.save(options).then((uris: string[]) => {
        this.downloadUriPending = false;
        if (uris.length > 0 && uris[0] !== '') {
          this.downloadUri = uris[0];
          hilog.info(DOMAIN, TAG, 'download uri: %{public}s', this.downloadUri);
        } else {
          hilog.warn(DOMAIN, TAG, 'download uri empty');
        }
      }).catch((err: BusinessError) => {
        this.downloadUriPending = false;
        hilog.warn(DOMAIN, TAG, 'ensure download uri failed: %{public}s', err.message);
      });
    } catch (e) {
      this.downloadUriPending = false;
      hilog.warn(DOMAIN, TAG, 'ensure download uri error: %{public}s', (e as Error).message);
    }
  }

  /** 写入公共下载目录；返回展示用位置前缀，失败返回空串 */
  private saveToPublicDownload(name: string, data: ArrayBuffer): string {
    if (this.downloadUri === '') {
      return '';
    }
    try {
      const base = this.downloadUri.replace(/\/+$/, '');
      // 官方机制：自动创建在 Download/包名/ 目录（系统强制包名子目录，不可自定义）
      const destPath = new fileUri.FileUri(base + '/' + name).path;
      const fp = fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(fp.fd, data);
      fileIo.closeSync(fp);
      hilog.info(DOMAIN, TAG, 'public save ok: %{public}s', destPath);
      return '下载/';
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'public save failed: %{public}s', (e as Error).message);
      return '';
    }
  }

  private saveDshDownload(url: string): void {
    if (this.downloading) {
      return;
    }
    this.downloading = true;
    if (!url.startsWith('http')) {
      this.downloading = false;
      promptAction.showToast({ message: '下载类型不支持' });
      return;
    }
    // 直接走系统下载（权限静默：若公共搬移被拒则保留沙箱并提示）
    this.doSystemDownload(url);
  }

  /** 手动 HTTP 下载（@ohos.net.http，绕开 request 下载服务在 ArkWeb 回调中的崩溃）：
   * Cookie 认证 -> 内存 -> 写基础 filesDir/downloads（沙箱兜底） */
  private doSystemDownload(url: string): void {
    let cookie = '';
    try {
      cookie = webview.WebCookieManager.fetchCookieSync(url);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'fetch cookie failed: %{public}s', (e as Error).message);
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: { 'Cookie': cookie },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 120000,
      connectTimeout: 30000
    };
    httpRequest.request(url, options).then((res: http.HttpResponse) => {
      httpRequest.destroy();
      if (res.responseCode !== 200) {
        this.downloading = false;
        hilog.warn(DOMAIN, TAG, 'http %{public}d for %{public}s', res.responseCode, url);
        promptAction.showToast({ message: '下载失败 (HTTP ' + res.responseCode + ')' });
        return;
      }
      const data: ArrayBuffer = res.result as ArrayBuffer;
      if (data.byteLength === 0) {
        this.downloading = false;
        promptAction.showToast({ message: '下载数据为空' });
        return;
      }
      const name = this.downloadName(url);
      // 优先：公共下载目录（DOWNLOAD 模式持久化 URI；无 UI、自动进 下载/包名/）
      const savedWhere = this.saveToPublicDownload(name, data);
      if (savedWhere.length > 0) {
        this.downloading = false;
        hilog.info(DOMAIN, TAG, 'download ok (public): %{public}s %{public}d bytes', name, data.byteLength);
        promptAction.showToast({ message: '已保存到 ' + savedWhere + name });
        return;
      }
      // 兜底：应用沙箱
      const dir = ctx.filesDir + '/downloads';
      try {
        if (!fileIo.accessSync(dir)) {
          fileIo.mkdirSync(dir);
        }
      } catch (e) {
      }
      const filePath = dir + '/' + name;
      const fp = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(fp.fd, data);
      fileIo.closeSync(fp);
      this.downloading = false;
      hilog.info(DOMAIN, TAG, 'download ok (sandbox): %{public}s %{public}d bytes', name, data.byteLength);
      promptAction.showToast({ message: '已保存到应用目录: ' + name });
    }).catch((err: BusinessError) => {
      httpRequest.destroy();
      this.downloading = false;
      hilog.warn(DOMAIN, TAG, 'http download error: %{public}s', err.message);
      promptAction.showToast({ message: '下载失败: ' + err.message });
    });
  }

  /** 从 URL 推断导出文件名（dsh-pocket: /api/session.export?sessionId=<id>） */
  private downloadName(url: string): string {
    const q = url.split('?')[1] ?? '';
    const m = q.match(/sessionId=([^&]+)/);
    if (m && m.length > 1) {
      return 'dsh-session-' + m[1] + '.zip';
    }
    return 'dsh-export-' + Date.now() + '.zip';
  }

  // 悬浮操作条已移除（用户需求：不再干扰网页交互）——保留函数体会占用业务域，直接删除
  // 【删除标记】FloatingBar/FloatMenu 若未来恢复，从 git 历史 53ec5c5 前的版本取回

  /** 光感悬浮菜单（半透明毛玻璃 + 圆角 + 阴影） */

  private clearWebData(): void {
    // 均为同步 API（WebStorage.deleteAllData / WebCookieManager.clearAllCookiesSync）
    webview.WebStorage.deleteAllData();
    webview.WebCookieManager.clearAllCookiesSync();
    hilog.info(DOMAIN, TAG, 'web storage & cookies cleared');
  }

  @Builder
  ErrorView() {
    Column({ space: 16 }) {
      Text('⚠')
        .fontSize(48)
      Text(this.failText)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      Row({ space: 12 }) {
        Button('重试')
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onRetry();
          })
        Button('返回首页')
          .backgroundColor($r('app.color.button_surface'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.backHome();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  SidePanel() {
    Column({ space: 12 }) {
      Text('当前连接')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .alignSelf(ItemAlign.Start)
      Text(UrlUtils.display(this.url, 32))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .alignSelf(ItemAlign.Start)
      Button('刷新')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.onRefresh();
        })
      Button('返回首页')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.backHome();
        })
      Blank()
      Text('口袋工作台 · 配合电脑端插件使用')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width(220)
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.panel_background'))
  }

  build() {
    // Web 占满方案：网页避让状态栏；状态栏底色随主题（浅色白/深色黑），底部扩展至屏幕底
    Column() {
      this.Main()
    }
    .width('100%')
    .height('100%')
    // 状态栏底色条：跟随网页实际外观（浅色白 / 深色 #151517），网页内容保持避让
    .backgroundColor(this.stripBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.statusBarH })
  }

  @Builder
  Main() {
    Row() {
      if (this.wide) {
        this.SidePanel()
      }
      Column() {
        Stack() {
          // Web 铺满（顶部让出状态栏：内容层默认安全区避让；底部扩展至屏幕底）
          if (this.failed) {
            this.ErrorView()
          } else {
            Web({ src: this.url, controller: this.controller })
              .javaScriptAccess(true)
              // darkMode Auto：跟随系统（网页"跟随系统"模式时生效）；
              // forceDarkAccess 关闭：网页内可独立切换浅/深外观，不被系统深色强制转深
              .darkMode(WebDarkMode.Auto)
              .forceDarkAccess(false)
              .domStorageAccess(true)
              .zoomAccess(false)
              .overScrollMode(OverScrollMode.NEVER)
              .onProgressChange((event: OnProgressChangeEvent) => {
                this.progress = event.newProgress;
              })
              .onPageBegin(() => {
                this.loading = true;
              })
              .onDownloadStart((event: OnDownloadStartEvent) => {
                this.saveDshDownload(event.url ?? '');
              })
              .onPageEnd(() => {
                this.loading = false;
                this.failed = false;
                this.pollWebTheme();
              })
              .onTitleReceive((event: OnTitleReceiveEvent) => {
                const t = event.title ?? '';
                if (t.length > 0) {
                  this.title = t;
                }
              })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                // 延迟确认：刷新/重载过程中的瞬时错误（如 ERR_ABORTED）不直接显示错误页，
                // 等 800ms；若页面已恢复（onPageEnd）则忽略。
                const info = event.error?.getErrorInfo() ?? 'unknown';
                hilog.error(DOMAIN, TAG, 'web error: %{public}s', info);
                const self = this;
                setTimeout(() => {
                  // 若在等待期间页面已结束加载，说明瞬时错误已恢复
                  if (!self.failed && self.loading) {
                    self.failed = true;
                    self.failText = '网络错误：无法连接 ' + UrlUtils.display(self.url, 32);
                    self.loading = false;
                  }
                }, 800);
              })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                // HTTP 状态码不拦截：dsh-pocket 的 PIN 页/登录挑战/子资源 401 都交给页面自身处理
                const code = event.response?.getResponseCode() ?? 0;
                hilog.info(DOMAIN, TAG, 'http %{public}d for %{public}s', code, UrlUtils.display(this.url, 24));
              })
              .width('100%')
              .height('100%')
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
              .multiWindowAccess(true)
              .allowWindowOpenMethod(true)
              .onWindowNew((event: OnWindowNewEvent) => {
                // 单窗口策略：DSH 域内 URL 在当前 Web 加载；外部域名交给系统浏览器（避免经 dsh-pocket 代理失败）
                const newUrl = event.targetUrl ?? '';
                hilog.info(DOMAIN, TAG, 'window.open request: %{public}s', newUrl);
                if (newUrl.length > 0) {
                  const baseHost = UrlUtils.hostOf(this.url);
                  const extHost = UrlUtils.hostOf(newUrl);
                  if (baseHost.length > 0 && extHost !== baseHost) {
                    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                    ctx.openLink(newUrl).catch(() => {
                    });
                  } else {
                    this.controller.loadUrl(newUrl);
                  }
                }
                event.handler.setWebController(null);
              })
          }

          if (this.loading && this.progress > 0 && this.progress < 100) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .color($r('app.color.primary'))
              .width('100%')
              .height(2)
              .position({ x: 0, y: 0 })
          }

          // 相册图片 → 输入框（右下悬浮，沉浸光感）
          Button() {
            SymbolGlyph($r('sys.symbol.ohos_photo'))
              .fontSize(20)
              .fontColor([$r('app.color.text_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor('#26000000')
          .position({ x: '80%', y: '86%' })
          .onClick(() => {
            this.pickAndInjectImage();
          })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.stripBg())
      }
      .layoutWeight(1)
      .height('100%')
      .width('100%')
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      const w = newValue.width as number;
      const nowWide = w >= AppConstants.WIDE_BREAKPOINT;
      if (nowWide !== this.wide) {
        hilog.info(DOMAIN, TAG, 'window width changed: %{public}d vp, wide=%{public}s', w, nowWide);
      }
      this.wide = nowWide;
    })
  }
}
