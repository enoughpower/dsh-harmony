## v2.0.2(2026-09-20)

### 亮点

- 📑 **首页双 Tab**：官方 UI Design Kit `HdsTabs` 悬浮胶囊 TabBar（光感沉浸材质）；会话列表按工作区（cwd）分组，下拉刷新强制重建修复
- 💰 **Kimi 余额卡**：与 DeepSeek 余额卡同款样式；密钥读 `MOONSHOT_API_KEY`，端点 `api.moonshot.cn`；余额圆环 5 分钟倒计时结束自动刷新并重置（修复停在 0 不刷新）
- 🗂 **归档会话过滤**：电脑端 push-notify 新增 `/api/archived`（读取 DSH `workspace.json`），App 会话列表与「最新会话」隐藏已归档会话，与 WebShell 一致
- 💬 **会话详情增强**：点空白区域取消文字选中；**平板宽屏下详情内嵌左栏**（与设置/历史同层级），右侧控制台保持可见，不再全屏
- 🔀 **连接健壮性**：RPC 短窗去重（800ms 合并同端点请求）+ 5xx/530 自动重试一次
- 🎨 **深色模式**：TabBar 底部渐变遮罩跟随系统主题（深色不再发白）
- 🧹 **精简**：移除自实现的相册图片注入入口（保留原生详情页带图发送）
- 📦 **上架准备（AppGallery）**：
  - 移除受限权限 `READ_WRITE_DOWNLOAD_DIRECTORY`，上架包仅 3 个权限：INTERNET / GET_NETWORK_INFO / CAMERA
  - 新增 `FeatureFlags.BALANCE_ENABLED`：上架版不显示余额卡、不发起 `:3082` 请求
  - 重写 `scripts/build-store.sh`：`--check` 上架体检（权限白名单/开关/签名）、`--install` 商店版行为包侧载验收、`versionCode` 注入、SHA256 与签名校验
  - 新增 `docs/STORE.md`：上架功能清单、权限说明、提审清单

### 其他

- 安装包：附带的 HAP 为 **release 签名**（发布证书），供云测/平台侧载；本机调试安装请自行用 debug 签名包
- 版本：`versionName 2.0.2` / `versionCode 1000007`
- 详细变更见 [CHANGELOG.md](../CHANGELOG.md)
