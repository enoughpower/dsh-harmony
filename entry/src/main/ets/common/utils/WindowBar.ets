import { window } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';

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

  /** 页面背景色（跟随深浅色） */
  static pageBackground(context: common.Context): SystemBarPalette {
    const uiCtx = context as common.UIAbilityContext;
    const dark = uiCtx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    return dark ? { bg: '#121417', fg: '#FFFFFF' } : { bg: '#F7F8FA', fg: '#000000' };
  }
}
