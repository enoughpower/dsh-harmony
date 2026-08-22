import { webview } from '@kit.ArkWeb';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConstants } from '../common/constants/AppConstants';
import { UrlUtils } from '../common/utils/UrlUtils';

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
  @State title: string = 'DSH';
  @State loading: boolean = true;
  @State progress: number = 0;
  @State failed: boolean = false;
  @State failText: string = '';
  @State wide: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
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
    this.controller.refresh();
  }

  private onRefresh(): void {
    this.loading = true;
    this.controller.refresh();
  }

  private backHome(): void {
    router.back();
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      Button('←')
        .width(36)
        .height(36)
        .fontSize(16)
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          if (this.controller.accessBackward()) {
            this.controller.backward();
          } else {
            this.backHome();
          }
        })
      Text(this.title)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button('↻')
        .width(36)
        .height(36)
        .fontSize(16)
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.onRefresh();
        })
      Button('≡')
        .width(36)
        .height(36)
        .fontSize(16)
        .backgroundColor($r('app.color.button_surface'))
        .fontColor($r('app.color.text_primary'))
        .bindMenu([
          {
            value: '返回首页',
            action: () => {
              this.backHome();
            }
          },
          {
            value: '清除 Web 数据',
            action: () => {
              this.clearWebData();
            }
          }
        ])
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

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
      Text('DSH Harmony · 配合 dsh-pocket 使用')
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
    Row() {
      if (this.wide) {
        this.SidePanel()
      }
      Column() {
        this.TopBar()
        if (this.failed) {
          this.ErrorView()
        } else {
          Stack() {
            Web({ src: this.url, controller: this.controller })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .zoomAccess(false)
              .overScrollMode(OverScrollMode.NEVER)
              .onProgressChange((event: OnProgressChangeEvent) => {
                this.progress = event.newProgress;
              })
              .onPageBegin(() => {
                this.loading = true;
              })
              .onPageEnd(() => {
                this.loading = false;
                this.failed = false;
              })
              .onTitleReceive((event: OnTitleReceiveEvent) => {
                const t = event.title ?? '';
                if (t.length > 0) {
                  this.title = t;
                }
              })
              .onErrorReceive((event: OnErrorReceiveEvent) => {
                // 仅网络级错误（DNS 失败/连接拒绝/超时）显示错误页
                this.failed = true;
                this.failText = '网络错误：无法连接 ' + UrlUtils.display(this.url, 32);
                this.loading = false;
                hilog.error(DOMAIN, TAG, 'web error: %{public}s', event.error?.getErrorInfo() ?? 'unknown');
              })
              .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
                // HTTP 状态码不拦截：dsh-pocket 的 PIN 页/登录挑战/子资源 401 都交给页面自身处理
                const code = event.response?.getResponseCode() ?? 0;
                hilog.info(DOMAIN, TAG, 'http %{public}d for %{public}s', code, UrlUtils.display(this.url, 24));
              })
              .width('100%')
              .height('100%')

            if (this.loading && this.progress > 0 && this.progress < 100) {
              Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
                .color($r('app.color.primary'))
                .width('100%')
                .height(2)
                .position({ x: 0, y: 0 })
            }
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')
        }
      }
      .layoutWeight(1)
      .height('100%')
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    // 保持默认安全区布局（不扩展，避免内容与状态栏重叠）
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
