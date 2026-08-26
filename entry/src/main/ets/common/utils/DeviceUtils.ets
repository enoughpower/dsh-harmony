/**
 * 设备/窗口布局判定。
 * 规则（用户确认）：仅"平板 + 横屏"触发双栏；手机/平板竖屏保持单栏。
 * 容器用 onAreaChange 拿宽高判断横竖屏，这里提供设备类型与组合判定。
 */
import { deviceInfo } from '@kit.BasicServicesKit';

export class DeviceUtils {
  /** 是否平板 / 2in1（pad pc）：手机 false；折叠屏按其系统返回 */
  static isTablet(): boolean {
    const t = deviceInfo.deviceType;
    return t === 'tablet' || t === '2in1';
  }

  /** 是否触发双栏：平板/pad-pc 且横屏（宽>高）。竖屏或手机均 false。 */
  static shouldSplitTabletLandscape(width: number, height: number): boolean {
    return DeviceUtils.isTablet() && width > height;
  }
}
