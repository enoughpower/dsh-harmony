# 上架（AppGallery）整理

> 目标：同一分支同时产出「全功能版（自用/开源，带推送）」与「上架版（AppGallery）」，上架版由 `scripts/build-store.sh` 自动裁剪。

## 1. 功能清单：哪些能上架

| 功能 | 上架版 | 说明 |
| --- | --- | --- |
| 扫码连接 | ✅ 保留 | ScanKit；仅需 CAMERA（user_grant） |
| 连接历史 / 手动输入 | ✅ 保留 | 只存连接地址，PIN/凭证不落盘 |
| ArkWeb 控制台（局域网 / 隧道） | ✅ 保留 | 加载用户自己电脑的 dsh-pocket 地址 |
| 原生会话列表 / 详情 / 带图发送 / 控制 | ✅ 保留 | 数据来自用户自建电脑服务 |
| 连接自动切换（IP ↔ 隧道） | ✅ 保留 | 本地网络探测 |
| 平板/折叠屏双栏、底部 TabBar | ✅ 保留 | UI 自适应 |
| 全局沉浸式状态栏、深/浅色 | ✅ 保留 | 无隐私影响 |
| 桌面服务卡片 | ✅ 保留 | 显示最近连接 / 最新会话 |
| 余额卡（DeepSeek / Kimi） | ⛔ 上架版关闭 | 依赖用户电脑本地部署 push-notify(:3082) + API Key；上架版 `BALANCE_ENABLED=false`：不显示卡片、不发起 :3082 余额请求 |
| 导出 / 下载 | ✅ 保留（降级） | 改走系统文件选择器，不申请受限权限 |
| Push Kit 推送 / 通知权限 | ⛔ 上架版关闭 | `FeatureFlags.PUSH_ENABLED=false`：不建 token、不申请通知、隐藏推送状态行 |
| AGC 配置 agconnect-services.json | ⛔ 不入包 | 构建期间临时移出 |
| `READ_WRITE_DOWNLOAD_DIRECTORY` | ⛔ 移除 | 受限权限（需 ACL），上架不可用；已从 module.json5 永久删除 |
| `tools/push-notify/` | ⛔ 无关 | 电脑端工具，不参与 App 打包 |

## 2. 上架包权限（仅 3 个）

| 权限 | 类型 | 用途 |
| --- | --- | --- |
| `ohos.permission.INTERNET` | normal | 访问用户电脑端 dsh-pocket / DSH |
| `ohos.permission.GET_NETWORK_INFO` | normal | 判断网络变化并自动切换连接 |
| `ohos.permission.CAMERA` | user_grant | 扫描连接二维码 |

任何新增权限都会被 `build-store.sh --check` 白名单拦下。

## 3. 签名与版本

- 上架包使用 **product=release**（发布证书 `build-profile.json5 → signingConfigs.release`），产物为 **`.app`**。
- `versionCode` 必填且递增；`versionName` 在 `AppScope/app.json5`。
- API 26 起版本号用 SemVer `X.Y.Z`（构建配置写 `"26.0.0"`，不要写 `26.0.0(26)`）。
- AGC 应用信息（bundleName `com.dsh.lite`、发布证书指纹）需与上传包一致。

## 4. 构建

```bash
./scripts/build-store.sh --check        # 上架体检：权限白名单 / 推送开关 / 签名配置 / 工作区
./scripts/build-store.sh 1000007        # 构建上架包 → release/DSH-Harmony-store-1000007-YYYYMMDD.app
./scripts/build-store.sh 1000007 myname # 自定义产物名
ALLOW_DIRTY=1 ./scripts/build-store.sh --check   # 允许工作区有未提交改动
```

脚本行为：临时置 `PUSH_ENABLED=false`、`BALANCE_ENABLED=false` → 移出 AGC 配置 → 改 `versionCode` → `assembleApp(product=release)` → 复制到 `release/` → 打印 SHA256 → 尝试 `hap-sign-tool verify-app`；**退出时自动还原**所有临时改动。

## 5. 上架前检查清单

- [ ] `./scripts/build-store.sh --check` 通过
- [ ] 应用图标（`release/icon/`）、截图（`release/screenshots/`）、应用简介/版本说明
- [ ] 隐私政策：本应用仅保存连接地址，不采集个人信息、不上传用户数据（需在商店后台填写）
- [ ] 权限说明：相机仅用于扫码；网络仅用于连接用户自己的电脑
- [ ] 发布证书与 AGC 应用指纹一致；`versionCode` 高于线上版本
- [ ] 目标设备：phone / tablet；兼容 SDK 与 API 26 构建验证通过
- [ ] 内容合规：应用不内置内容，作为远程连接工具使用

## 6. 与全功能版的差异

| 项 | 全功能版（master 默认） | 上架版 |
| --- | --- | --- |
| `FeatureFlags.PUSH_ENABLED` | true | false（构建时临时） |
| `FeatureFlags.BALANCE_ENABLED` | true | false（构建时临时；不显示余额卡、不请求 :3082） |
| AGC `agconnect-services.json` | 打包进 rawfile | 构建时移出 |
| 通知权限 | 首启申请 | 不申请 |
| 推送状态行 / 余额推送 | 显示 | 隐藏 |
| 签名 | default（调试/侧载） | release（发布证书） |
| 产物 | `.hap`（hdc 安装） | `.app`（AppGallery 上传） |