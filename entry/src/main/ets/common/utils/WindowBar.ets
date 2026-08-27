import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/** 系统栏配色 */
export interface SystemBarPalette {
  bg: string;
  fg: string;
}

/**
 * 页面级系统栏颜色控制。
 * 说明：WebShell 页面背景与网页一致（白色），系统栏需跟随页面而非全局默认。
 */
export class WindowBar {
  static async set(context: common.Context, backgroundColor: string, contentColor: string): Promise<void> {
    try {
      const win = await window.getLastWindow(context);
      await win.setWindowSystemBarProperties({
        statusBarColor: backgroundColor,
        navigationBarColor: backgroundColor,
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      });
    } catch (e) {
      // 忽略：窗口未就绪等
    }
  }

  /** 全局沉浸式（统一入口）：全屏布局 + 透明状态栏/导航栏，内容色随深浅色。
   *  dark 缺省 = 按系统主题；显式传入 = 跟随调用方判定（如 WebShell 网页内主题可能与系统不同）。 */
  static async immersive(context: common.Context, dark?: boolean): Promise<void> {
    try {
      const fg = dark === undefined
        ? WindowBar.pageBackground(context).fg
        : (dark ? '#FFFFFF' : '#000000');
      const win = await window.getLastWindow(context);
      await win.setWindowLayoutFullScreen(true);
      await win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: fg,
        navigationBarContentColor: fg
      });
    } catch (e) {
      // 忽略：窗口未就绪等
    }
  }

  /** 状态栏高度（vp）。px 转 vp 交由调用方 UIContext.px2vp。 */
  static statusBarHeight(context: common.Context, px2vp: (px: number) => number): Promise<number> {
    return window.getLastWindow(context).then((w: window.Window) => {
      const area = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      return px2vp(area.topRect.height);
    }).catch(() => 0);
  }

  /** 底部导航条/手势条高度（vp）。px 转 vp 交由调用方 UIContext.px2vp。 */
  static bottomBarHeight(context: common.Context, px2vp: (px: number) => number): Promise<number> {
    return window.getLastWindow(context).then((w: window.Window) => {
      const area = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      return px2vp(area.bottomRect.height);
    }).catch(() => 0);
  }

  /** 是否深色模式（ResourceManager 解析主题色,跟随系统;冷启动 config.colorMode=NOT_SET 时仍可靠） */
  static isDark(context: common.Context): boolean {
    try {
      // immersive_content: 浅色 #000000(R=0) / 深色 #FFFFFF(R=255)
      const v = context.resourceManager.getColorByNameSync('immersive_content');
      return ((v >>> 16) & 0xff) > 127;
    } catch (e) {
      const uiCtx = context as common.UIAbilityContext;
      return uiCtx.config?.colorMode === 1; // COLOR_MODE_DARK
    }
  }

  /** ARGB int 转 #RRGGBB */
  private static intToHex(c: number): string {
    const r = (c >>> 16) & 0xff;
    const g = (c >>> 8) & 0xff;
    const b = c & 0xff;
    const h = (n: number) => n.toString(16).padStart(2, '0');
    return '#' + h(r) + h(g) + h(b);
  }

  /** 页面背景色（ResourceManager 跟随系统解析;冷启动/换主题均可靠） */
  static pageBackground(context: common.Context): SystemBarPalette {
    try {
      const rm = context.resourceManager;
      return {
        bg: WindowBar.intToHex(rm.getColorByNameSync('page_background')),
        fg: WindowBar.intToHex(rm.getColorByNameSync('immersive_content'))
      };
    } catch (e) {
      return { bg: '#F7F8FA', fg: '#000000' };
    }
  }
}
