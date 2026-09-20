/**
 * 可复用特性开关（同一分支产出上架版 / 全功能版）。
 *
 * PUSH_ENABLED:
 *   true  → 全功能版（开源/自用，带 Push Kit）：
 *           上报设备 push token、申请通知权限、首页推送状态行、余额/会话推送
 *   false → 上架商店版（AppGallery）：
 *           不建/不报 token、不申请通知权限、隐藏推送状态行，电脑端推送服务也无需运行
 *
 * 说明：上架版同时不打包 AGC 配置（entry/src/main/resources/rawfile/agconnect-services.json），
 *       构建时由 scripts/build-store.sh 临时移出并在结束后还原。
 *
 * 切换：scripts/build-store.sh 构建上架包时临时置为 false（构建后还原）；master 默认 true。
 */
export class FeatureFlags {
  static readonly PUSH_ENABLED: boolean = true;
}
