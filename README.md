# DSH Harmony

DeepSeek Harness 的 **HarmonyOS 原生客户端**，与 [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) 插件配套使用：手机扫一扫电脑端 DSH 设置页的二维码，即可在手机上实时使用电脑上的 DeepSeek Harness。

> 📱 目标系统：HarmonyOS 7.0（手机 / 折叠屏 / 平板） · 短期自用，不上架应用市场
> 🇬🇧 English: [README.en.md](README.en.md)

## 特性

- 📷 **扫码即连**：自绘沉浸扫码页（状态栏透明、微信式渐变扫描线、光感圆钮 ×/🔦）；扫码 → 校验 → 打开 ArkWeb
- 🔌 **配合 dsh-pocket**：局域网（`http://IP:3081`）与公网（cloudflared 隧道）地址均可
- 📱 **多形态自适应**：手机竖屏单栏；折叠屏展开 / 平板横屏自动切换为「侧栏 + Web」双栏
- 🧭 **连接历史**：按 IP 去重、时间倒序、左滑删除、点击直达；首页常驻最近一条，支持手动输入地址
- ⚡ **自动连接**：设置开关开启后，每次进入 App 自动连接历史中最近的 IP（免扫码免扫描）
- 📥 **导出自动保存**：会话日志导出自动落到手机「下载」目录（零弹窗，`下载/com.dsh.lite/`）
- ⚡ **最新会话速览**：首页卡片与桌面小组件显示最新会话（标题/进行中/轮次/步骤/相对时间，标题自动换行，点击刷新）
- 📇 **服务卡片**：桌面小组件显示连接状态、最近使用时间与最新会话，点击直达 DSH
- 🛡️ **隐私友好**：只存连接地址，PIN / 凭证不落盘；设置页可一键清空 Web 数据与历史
- 🔧 **完整工具链**：命令行构建 / 真机冒烟 / Hypium 单测 / GitHub Actions CI

## 工作原理

```
DSH Harmony (ArkWeb)
   │  扫码拿到 URL
   ▼
dsh-pocket 代理（电脑 :3081）── 改写 Host/Origin 为 loopback，绕过浏览器信任栅栏
   │  网页内 8 位 PIN 认证（App 不参与）
   ▼
DeepSeek Harness web（电脑 :3080）
```

dsh-pocket 安装与使用见其 [README](https://github.com/shaobeichen/dsh-pocket)。

## 环境要求

| 项 | 要求 |
| --- | --- |
| 系统 | HarmonyOS 7.0（API 版本以手机「关于本机」为准） |
| 开发 | DevEco Studio 6.x（含 SDK / hvigor / ohpm / hdc） |
| 设备 | 开启 USB 调试的鸿蒙手机 / 折叠屏 / 平板 |

> 本工程配置：`targetSdkVersion = 6.1.1(24)`（本机 DevEco 6.1.1 SDK），`compatibleSdkVersion = 6.0.0(20)`；手机 7.0.1(25) 完全兼容运行，待工具链提供 API 25 SDK 后可升级 targetSdkVersion。

## 快速开始

1. 电脑端：在 DSH 中安装 dsh-pocket 插件，打开「手机访问」设置页，得到二维码
2. 手机端：安装 DSH Harmony（构建或 Release 下载 HAP，`hdc install -r` 或本地安装）
3. 打开 App → 「扫码连接」扫电脑屏幕上的二维码 → 自动进入 DSH 界面
4. 之后打开 App 可从历史记录一键直达；公网连接需在网页内输入 dsh-pocket 设置的 8 位 PIN

## 本地开发

```bash
./scripts/dev-tools.sh          # 探测 DevEco/SDK/hvigor/ohpm/hdc 路径
./scripts/build.sh              # 构建 debug HAP（输出 entry/build/.../*.hap）
./scripts/build.sh release      # release 构建（未签名）
./scripts/build.sh --install    # 构建并安装到已连接设备
./scripts/smoke.sh              # 真机冒烟：安装→启动→UI 校验→日志检查→卸载
./scripts/unit-test.sh          # 单测（需设备；或在 DevEco 内 Run Test 配置）
./scripts/gen-changelog.sh      # 按天生成 CHANGELOG 片段
```

工具链路径可用环境变量覆盖（`DEVECO_HOME` / `DEVECO_SDK_HOME` / `HVIGORW` / `OHPM` / `HDC`），CI 场景必须显式提供。

### 测试

测试分层与规范详见 [docs/TESTING.md](docs/TESTING.md)：

- 单元测试（Hypium）：`entry/src/test/`，覆盖 URL 校验与连接模型序列化
- UI 冒烟（ohosTest）：启动 → 断言首页元素
- 真机冒烟：`scripts/smoke.sh`（uitest dumpLayout 校验 + hilog 错误检查）

## 项目结构

```
├── AppScope/              应用级配置（bundleName: com.dsh.lite）
├── entry/                 主模块
│   └── src/main/ets/
│       ├── entryability/  EntryAbility（生命周期）
│       ├── pages/         Index（连接入口）/ WebShell（ArkWeb 套壳）/ SettingsPage
│       ├── components/    连接卡片、手动输入对话框
│       ├── common/        constants / utils / store
│       └── model/         数据模型
├── entry/src/test/        Hypium 单元测试
├── entry/src/ohosTest/    UI 冒烟测试
├── scripts/               构建/测试/冒烟/changelog 工具
├── .github/workflows/     CI（构建 + 签名 + Release）
├── .agents/skills/        本地开发技能（编码/Review 规范，gitignore，不对外）
└── docs/                  架构设计等文档
```

## CI（GitHub Actions）

- push / PR：ohpm install → assembleHap（debug），产物上传 artifact
- tag `v*`：release 构建 + 签名（配置 secrets）→ GitHub Release 发布
- 构建环境：华为官方「HarmonyOS 独立命令行工具包」（内嵌 SDK），在 ubuntu runner 上自动下载安装

**首次使用 CI 需要提供工具包**（本仓库已用 GitHub Release 分发方案，`CLT_URL` 已配置）：

| 方案 | 说明 |
| --- | --- |
| Release 分发（本仓库当前方案） | `gh release upload` 上传工具包到 Release，`CLT_URL` 指向资产 URL |
| 华为下载中心直链 | workflow_dispatch 输入框粘贴，或设置 variable `CLT_URL` / `CLT_SHA256` |
| 本地下载 | 下载工具包到本地后上传到 Release（注意 GitHub 单文件 2GiB 上限，分卷需拆分） |

工具包获取：登录 [华为开发者联盟下载中心 - Command Line Tools](https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos)，选择 **Linux x64** 且与工程 SDK（6.1.1(24)）匹配的版本（6.1.1.300）。

签名 secrets：`SIGNING_KEY`（p12 base64）/ `SIGNING_CERT` / `SIGNING_PROFILE` / `KEYSTORE_PASSWORD` / `KEY_PASSWORD` / `KEY_ALIAS`

## 变更记录

变更按天记录在 [CHANGELOG.md](CHANGELOG.md)，约定提交信息使用 Conventional Commits 前缀（feat/fix/perf/docs/test/chore/refactor），可用 `scripts/gen-changelog.sh` 自动生成当天片段。

## 参考项目

- [dsh-pocket](https://github.com/shaobeichen/dsh-pocket) —— 本 App 的服务端插件
- [hongshuxifan321/dsh-mobile-app](https://github.com/hongshuxifan321/dsh-mobile-app) —— 同类 Android 壳应用（Basic Auth + Keystore 存储，可参考）
- [ohosvscode/harmony-next-pipeline](https://github.com/ohosvscode/harmony-next-pipeline) —— CI 构建方案参考

## License

MIT
