/**
 * 设备/窗口布局判定。
 * 规则（用户确认）：平板默认双栏；折叠屏手机"展开+横屏"也双栏；普通手机锁竖屏单栏。
 * 容器用 onAreaChange 拿窗口宽高判断横竖屏。
 */
import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';

export class DeviceUtils {
  /** 是否平板 / 2in1（pad pc）；普通手机 false */
  static isTablet(): boolean {
    const t = deviceInfo.deviceType;
    return t === 'tablet' || t === '2in1';
  }

  /** 是否为"大屏"(平板 / 折叠屏展开)：display 宽度换算 vp >= 600（普通手机竖屏约 360vp） */
  static isLargeDisplay(): boolean {
    try {
      const d = display.getDefaultDisplaySync();
      const vpWidth = d.width * 160 / d.densityDPI;
      return vpWidth >= 600;
    } catch (e) {
      return DeviceUtils.isTablet();
    }
  }

  /** 是否触发双栏：平板默认双栏；或大屏(折叠屏展开)且横屏(宽>高)。普通手机 false。 */
  static shouldSplit(width: number, height: number): boolean {
    if (DeviceUtils.isTablet()) {
      return true;
    }
    return DeviceUtils.isLargeDisplay() && width > height;
  }
}
