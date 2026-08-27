/**
 * 可复用特性开关。
 * PUSH_ENABLED = true  → 全功能/开源版(带推送)：上报 token、申请通知权限、首页推送状态行
 * PUSH_ENABLED = false → 上架商店版(无推送)：跳过推送,不报 token、不申请通知权限、隐藏推送状态行
 *
 * 切换：scripts/build-store.sh 构建上架包时临时置为 false(构建后还原)；master 默认 true。
 */
export class FeatureFlags {
  static readonly PUSH_ENABLED: boolean = true;
}
