import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { picker, fileUri, fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { UrlUtils } from '../common/utils/UrlUtils';
import { WindowBar } from '../common/utils/WindowBar';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * WebShellView：dsh-pocket 网页的 ArkWeb 套壳展示（可复用）。
 * 供「窄屏 WebShell 页」与「宽屏右栏」两处使用；
 * 只负责 Web 渲染/进度/下载/图片注入/主题，不含页面级路由与左右分栏。
 */
@Component
export struct WebShellView {
  /** 当前加载的连接地址（父容器切换连接时更新） */
  @Prop url: string = '';
  /** 状态栏高度（沉浸式时进度条/内容避让；父容器实测后传入） */
  @Prop statusBarH: number = 0;
  @State title: string = '口袋工作台';
  @State loading: boolean = true;
  @State progress: number = 0;
  @State failed: boolean = false;
  @State failText: string = '';
  /** 网页实际外观：-1 未知 / 0 浅色 / 1 深色（网页内可独立于系统切换） */
  @State webDark: number = -1;
  @StorageLink('osThemeIsDark') @Watch('onThemeChange') osThemeIsDark: boolean = false;
  private themeTimer: number = -1;
  private controller: webview.WebviewController = new webview.WebviewController();
  private refreshing: boolean = false;
  private downloading: boolean = false;
  private downloadUri: string = '';
  private downloadUriPending: boolean = false;

  onThemeChange(): void { this.applyWebBar(); }

  private stripBg(): string {
    if (this.webDark === 1) return '#151517';
    if (this.webDark === 0) return '#FFFFFF';
    return this.osThemeIsDark ? '#151517' : '#FFFFFF';
  }

  private applyWebBar(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dark = this.webDark >= 0 ? this.webDark === 1 : this.osThemeIsDark;
    WindowBar.immersive(ctx, dark).catch(() => {});
  }

  private pollWebTheme(): void {
    const js = "(function(){" +
      "function bg(el){var c=getComputedStyle(el).backgroundColor;" +
      "var m=c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);return m?m:null;}" +
      "var m=bg(document.body)||bg(document.documentElement);" +
      "if(!m||m[1]==='0'&&m[2]==='0'&&m[3]==='0'){return -1;}" +
      "var lum=0.299*(+m[1])+0.587*(+m[2])+0.114*(+m[3]);" +
      "return lum<100?1:0;" + "})()";
    try {
      this.controller.runJavaScript(js).then((ret: string) => {
        const v = parseInt(ret, 10);
        if ((v === 0 || v === 1) && this.webDark !== v) {
          this.webDark = v;
          this.applyWebBar();
        }
      }).catch(() => {});
    } catch (e) {}
  }

  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(true);
    this.applyWebBar();
    if (this.themeTimer < 0) {
      this.themeTimer = setInterval(() => { this.pollWebTheme(); }, 1200);
    }
    const raw = this.url;
    const normalized = UrlUtils.normalize(raw);
    if (normalized !== null) {
      this.title = UrlUtils.display(normalized, 24);
    }
  }

  aboutToDisappear(): void {
    if (this.themeTimer >= 0) { clearInterval(this.themeTimer); this.themeTimer = -1; }
  }

  onPageShow(): void {
    this.applyWebBar();
    this.ensureDownloadUri();
    this.pollWebTheme();
  }

  private onRetry(): void {
    this.failed = false; this.failText = ''; this.loading = true;
    try { this.controller.refresh(); } catch (e) {}
  }

  private onRefresh(): void {
    if (this.refreshing) return;
    this.refreshing = true; this.loading = true;
    try { this.controller.refresh(); } catch (e) {}
    setTimeout(() => { this.refreshing = false; }, 1500);
  }

  private pickAndInjectImage(): void {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      photoPicker.select(options).then((result: photoAccessHelper.PhotoSelectResult) => {
        const uris = result.photoUris ?? [];
        if (uris.length === 0) return;
        this.injectImageToWeb(uris[0]);
      }).catch((e: BusinessError) => {});
    } catch (e) {}
  }

  private injectImageToWeb(uri: string): void {
    const doInject = (b64: string): void => {
      const name = 'dsh-upload-' + Date.now() + '.jpg';
      const js = "(function(){" +
        "try{" + "var b64='" + b64 + "';" + "var name='" + name + "';" +
        "var bin=atob(b64);" + "var bytes=new Uint8Array(bin.length);" +
        "for(var i=0;i<bin.length;i++){bytes[i]=bin.charCodeAt(i);}" +
        "var file=new File([bytes],name,{type:'image/jpeg'});" +
        "var dt=new DataTransfer();" + "dt.items.add(file);" +
        "document.dispatchEvent(new DragEvent('drop',{dataTransfer:dt,bubbles:true,cancelable:true}));" +
        "return 'ok';" + "}catch(e){return 'err:'+e.message;}" + "})()";
      this.controller.runJavaScript(js).then((ret: string) => {}).catch((e: BusinessError) => {});
    };
    let fp: fileIo.File | null = null;
    try { fp = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY); } catch (e) { return; }
    try {
      const imgSource = image.createImageSource(fp.fd);
      imgSource.createPixelMap().then((pm: image.PixelMap) => {
        const packer = image.createImagePacker();
        const opts: image.PackingOption = { 'format': 'image/jpeg', 'quality': 80 };
        packer.packing(pm, opts).then((data: ArrayBuffer) => {
          try { imgSource.release(); packer.release(); pm.release(); fileIo.closeSync(fp); } catch (e) {}
          const b64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
          doInject(b64);
        }).catch((e: BusinessError) => {});
      }).catch((e: BusinessError) => {});
    } catch (e) { try { fileIo.closeSync(fp); } catch (e2) {} }
  }

  private ensureDownloadUri(): void {
    if (this.downloadUri !== '' || this.downloadUriPending) return;
    this.downloadUriPending = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSaveOptions();
      options.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      const dp = new picker.DocumentViewPicker(ctx);
      dp.save(options).then((uris: string[]) => {
        this.downloadUriPending = false;
        if (uris.length > 0 && uris[0] !== '') { this.downloadUri = uris[0]; }
      }).catch((err: BusinessError) => { this.downloadUriPending = false; });
    } catch (e) { this.downloadUriPending = false; }
  }

  private saveToPublicDownload(name: string, data: ArrayBuffer): string {
    if (this.downloadUri === '') return '';
    try {
      const base = this.downloadUri.replace(/\/+$/, '');
      const destPath = new fileUri.FileUri(base + '/' + name).path;
      const fp = fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(fp.fd, data); fileIo.closeSync(fp);
      return '下载/';
    } catch (e) { return ''; }
  }

  private saveDshDownload(url: string): void {
    if (this.downloading) return;
    this.downloading = true;
    if (!url.startsWith('http')) { this.downloading = false; return; }
    if (url.startsWith('http')) {
      let cookie = '';
      try { cookie = webview.WebCookieManager.fetchCookieSync(url); } catch (e) {}
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const httpRequest = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET, header: { 'Cookie': cookie },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        readTimeout: 120000, connectTimeout: 30000
      };
      httpRequest.request(url, options).then((res: http.HttpResponse) => {
        httpRequest.destroy();
        if (res.responseCode !== 200) { this.downloading = false; return; }
        const data: ArrayBuffer = res.result as ArrayBuffer;
        if (data.byteLength === 0) { this.downloading = false; return; }
        const name = this.downloadName(url);
        if (this.saveToPublicDownload(name, data).length > 0) { this.downloading = false; return; }
        const dir = ctx.filesDir + '/downloads';
        try { if (!fileIo.accessSync(dir)) fileIo.mkdirSync(dir); } catch (e) {}
        const fp = fileIo.openSync(dir + '/' + name, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        fileIo.writeSync(fp.fd, data); fileIo.closeSync(fp);
        this.downloading = false;
      }).catch((err: BusinessError) => { httpRequest.destroy(); this.downloading = false; });
    }
  }

  private downloadName(url: string): string {
    const q = url.split('?')[1] ?? '';
    const m = q.match(/sessionId=([^&]+)/);
    if (m && m.length > 1) return 'dsh-session-' + m[1] + '.zip';
    return 'dsh-export-' + Date.now() + '.zip';
  }

  private clearWebData(): void {
    webview.WebStorage.deleteAllData();
    webview.WebCookieManager.clearAllCookiesSync();
  }

  @Builder
  ErrorView() {
    Column({ space: 16 }) {
      Text('⚠').fontSize(48)
      Text(this.failText).fontSize(15).fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center).padding({ left: 32, right: 32 })
      Row({ space: 12 }) {
        Button('重试').backgroundColor($r('app.color.primary')).onClick(() => { this.onRetry(); })
      }
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Stack() {
        if (this.failed) {
          this.ErrorView()
        } else {
          Web({ src: this.url, controller: this.controller })
            .javaScriptAccess(true)
            .darkMode(WebDarkMode.Auto)
            .forceDarkAccess(false)
            .domStorageAccess(true)
            .zoomAccess(false)
            .overScrollMode(OverScrollMode.NEVER)
            .onProgressChange((event: OnProgressChangeEvent) => { this.progress = event.newProgress; })
            .onPageBegin(() => { this.loading = true; })
            .onDownloadStart((event: OnDownloadStartEvent) => { this.saveDshDownload(event.url ?? ''); })
            .onPageEnd(() => { this.loading = false; this.failed = false; this.pollWebTheme(); })
            .onTitleReceive((event: OnTitleReceiveEvent) => {
              const t = event.title ?? '';
              if (t.length > 0) this.title = t;
            })
            .onErrorReceive((event: OnErrorReceiveEvent) => {
              const info = event.error?.getErrorInfo() ?? 'unknown';
              hilog.error(DOMAIN, TAG, 'web error: %{public}s', info);
              const self = this;
              setTimeout(() => { if (!self.failed && self.loading) { self.failed = true; self.failText = '网络错误：无法连接 ' + UrlUtils.display(self.url, 32); self.loading = false; } }, 800);
            })
            .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {})
            .width('100%').height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
            .multiWindowAccess(true)
            .allowWindowOpenMethod(true)
            .onWindowNew((event: OnWindowNewEvent) => {
              const newUrl = event.targetUrl ?? '';
              if (newUrl.length > 0) {
                const baseHost = UrlUtils.hostOf(this.url);
                const extHost = UrlUtils.hostOf(newUrl);
                if (baseHost.length > 0 && extHost !== baseHost) {
                  const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  ctx.openLink(newUrl).catch(() => {});
                } else { this.controller.loadUrl(newUrl); }
              }
              event.handler.setWebController(null);
            })
        }

        if (this.loading && this.progress > 0 && this.progress < 100) {
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .color($r('app.color.primary')).width('100%').height(2).position({ x: 0, y: 0 })
        }

        Button() {
          SymbolGlyph($r('sys.symbol.ohos_photo')).fontSize(20).fontColor([$r('app.color.text_primary')])
        }
        .width(44).height(44).borderRadius(22).backgroundColor('#26000000').position({ x: '80%', y: '86%' })
        .onClick(() => { this.pickAndInjectImage(); })
      }
      .layoutWeight(1).width('100%').backgroundColor(this.stripBg())
    }
    .width('100%').height('100%')
    .backgroundColor(this.stripBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.statusBarH })
  }
}
