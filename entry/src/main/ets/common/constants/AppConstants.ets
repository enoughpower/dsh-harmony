/**
 * 全局常量
 * 约定：所有魔法数字/字符串集中于此，禁止在业务代码中散落字面量。
 */
export class AppConstants {
  /** 应用名 */
  static readonly APP_NAME: string = '口袋工作台';
  /** Preferences 存储名 */
  static readonly STORE_NAME: string = 'dsh_harmony_store';
  /** 连接历史存储 key */
  static readonly KEY_CONNECTIONS: string = 'connections';
  /** 历史记录上限 */
  static readonly MAX_HISTORY: number = 20;
  /** 宽屏断点（vp）：>= 此值启用双栏布局（折叠屏展开态 / 平板横屏） */
  static readonly WIDE_BREAKPOINT: number = 840;
  /** dsh-pocket 代理默认端口 */
  static readonly DSH_POCKET_DEFAULT_PORT: number = 3081;
}
