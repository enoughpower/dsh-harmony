import { customScan, scanBarcode, scanCore } from '@kit.ScanKit';
import { router, promptAction, window, uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WindowBar } from '../common/utils/WindowBar';

const DOMAIN = 0x0000;
const TAG = 'DSHHarmony';

/**
 * 自绘扫码页：全黑沉浸（状态栏与页面同黑，无系统色块）+ 自定义取景框。
 * 识别成功：写入 pendingDshUrl -> 返回首页消费并打开。
 */
@Entry
@Component
struct ScanPage {
  @State vw: number = 360;
  @State vh: number = 780;
  @State msg: string = '';
  @State started: boolean = false;
  @State finishing: boolean = false;
  @State torchOn: boolean = false;
  @State scanLineY: number = 0;
  private xc: XComponentController = new XComponentController();

  /** 扫描线往复动画（框内 0 -> 高-4 -> 0 循环） */
  private startScanAnim(): void {
    const barH = 64;
    const maxY = 260 - barH;
    const ui = this.getUIContext();
    const run = (down: boolean): void => {
      if (this.finishing) {
        return;
      }
      ui.animateTo({
        duration: 1600,
        curve: Curve.EaseInOut,
        onFinish: () => {
          this.scanLineY = down ? maxY : 0;
          run(!down);
        }
      }, () => {
        this.scanLineY = down ? maxY : 0;
      });
    };
    run(true);
  }

  aboutToAppear(): void {
    this.measure();
    this.applyImmersive();
    this.startScanAnim();
  }

  onPageHide(): void {
    if (!this.finishing) {
      this.stopScan();
    }
    this.restoreWindow();
  }

  /** 全屏 + 透明状态栏：相机画面顶到屏幕最上（状态栏区域露出画面） */
  private applyImmersive(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowLayoutFullScreen(true);
        w.setWindowSystemBarProperties({
          'statusBarColor': '#00000000',
          'navigationBarColor': '#00000000',
          'statusBarContentColor': '#FFFFFF',
          'navigationBarContentColor': '#FFFFFF'
        });
      }).catch(() => {
      });
    } catch (e) {
    }
  }

  private restoreWindow(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowLayoutFullScreen(false);
      }).catch(() => {
      });
    } catch (e) {
    }
  }

  private measure(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        const rect = w.getWindowProperties().windowRect;
        this.vw = this.getUIContext().px2vp(rect.width);
        this.vh = this.getUIContext().px2vp(rect.height);
      }).catch(() => {
      });
    } catch (e) {
    }
  }

  private onSurfaceLoaded(): void {
    if (this.started) {
      return;
    }
    let surfaceId = '';
    try {
      surfaceId = this.xc.getXComponentSurfaceId();
    } catch (e) {
      this.msg = '相机组件初始化失败';
      return;
    }
    try {
      const options: scanBarcode.ScanOptions = {
        'scanTypes': [scanCore.ScanType.ALL],
        'enableMultiMode': false,
        'enableAlbum': false
      };
      customScan.init(options);
      const viewControl: customScan.ViewControl = {
        'width': this.vw,
        'height': this.vh,
        'surfaceId': surfaceId
      };
      customScan.start(viewControl, this.onResult);
      this.started = true;
      this.msg = '正在识别…';
    } catch (e) {
      this.msg = '启动扫码失败：' + (e as Error).message.slice(0, 40);
      this.stopScan();
    }
  }

  private onResult: AsyncCallback<scanBarcode.ScanResult[]> =
    (error: BusinessError, result: scanBarcode.ScanResult[]) => {
      if (this.finishing) {
        return;
      }
      if (error !== null && error !== undefined && result === undefined) {
        hilog.warn(DOMAIN, TAG, 'scan result error: %{public}s', error.message);
        this.msg = '扫码失败：' + error.message.slice(0, 40);
        return;
      }
      const list = result ?? [];
      if (list.length === 0) {
        return;
      }
      const raw = list[0].originalValue ?? '';
      hilog.info(DOMAIN, TAG, 'scan ok: %{public}s', raw);
      if (raw.length > 0) {
        AppStorage.setOrCreate('pendingDshUrl', raw);
      } else {
        promptAction.showToast({ message: '未识别到内容' });
      }
      this.stopScan();
    };

  private toggleTorch(): void {
    try {
      const status = customScan.getFlashLightStatus();
      if (status) {
        customScan.closeFlashLight();
        this.torchOn = false;
      } else {
        customScan.openFlashLight();
        this.torchOn = true;
      }
    } catch (e) {
      const em = (e as Error).message;
      hilog.warn(DOMAIN, TAG, 'flash failed: %{public}s', em);
      promptAction.showToast({ message: '手电筒不可用: ' + em.slice(0, 60) });
    }
  }

  private stopScan(): void {
    if (this.finishing) {
      return;
    }
    this.finishing = true;
    try {
      customScan.stop().then(() => {
        return customScan.release();
      }).catch(() => {
      });
    } catch (e) {
    }
    setTimeout(() => {
      router.back();
    }, 60);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      XComponent({
        id: 'scan-camera',
        type: XComponentType.SURFACE,
        controller: this.xc
      })
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onLoad(() => {
          this.onSurfaceLoaded();
        })

      // 取景框(260, 直角, 上移 30 → y = vh/2 - 160, 水平居中)
      Stack() {
        // 微信式渐变扫描条（素材 PNG：scan_line.png，上透明 -> 下实色，往复动效）
        Image($r('app.media.scan_line'))
          .width(252)
          .height(64)
          .objectFit(ImageFit.Fill)
          .position({ x: 4, y: this.scanLineY })
      }
      .width(260)
      .height(260)
      .border({ width: 2, color: '#FFFFFF' })
      .backgroundColor('#00000000')
      .position({ x: (this.vw - 260) / 2, y: this.vh / 2 - 160 })

      // 取消(往下挪, 避开状态栏)
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: false
      }))
      .position({ x: 20, y: 60 })
      .onClick(() => {
        this.stopScan();
      })

      // 手电筒(框正下方 50, 水平居中)
      Button() {
        SymbolGlyph($r('sys.symbol.flashlight_on_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: false
      }))
      .position({ x: (this.vw - 40) / 2, y: this.vh / 2 + 150 })
      .onClick(() => {
        this.toggleTorch();
      })

      // 文案(框下边 16, 水平居中)
      Text(this.msg.length > 0 ? this.msg : '将二维码放入取景框')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .width('100%')
        .textAlign(TextAlign.Center)
        .position({ x: 0, y: this.vh / 2 + 116 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
