# DSH Harmony 架构设计

> 状态：v1.0.0 初始设计（2026-08-23）。随开发持续修订。

## 1. 背景与目标

DSH Harmony 是 DeepSeek Harness（DSH）的 HarmonyOS 原生客户端，与 **dsh-pocket** 插件配套：

- 电脑端 DSH 安装 dsh-pocket 后，设置页出现二维码（局域网 `http://IP:3081` 或公网 `https://cloudflared隧道`）
- 手机扫码 → App 内 ArkWeb 直接加载该地址 → 与电脑端实时同屏操作 DSH
- v1.0 定位：WebView 套壳 + 扫码入口 + 连接管理；不引入复杂业务逻辑

## 2. 总体架构

```
┌────────────────────── DSH Harmony (HarmonyOS) ──────────────────────┐
│  pages/Index       连接入口：历史列表 / 扫码 / 手动输入 / 设置        │
│      │  UrlUtils.normalize 校验，ConnectionStore 持久化历史          │
│      ▼                                                               │
│  pages/WebShell    ArkWeb 套壳（核心）                               │
│    ├ 窄屏(<840vp)  顶部操作条 + Web 全屏 + 加载进度 + 错误页          │
│    └ 宽屏(≥840vp)  左侧连接侧栏 + 右侧 Web（折叠屏展开/平板横屏）     │
│      │  onBackPress 优先 Web 内后退                                   │
│      ▼                                                               │
│  pages/SettingsPage  历史清理 / Web 数据清理 / 关于                   │
└──────────────────────────────────────────────────────────────────────┘
                    │ https / http(局域网)
                    ▼
        dsh-pocket 代理（电脑 3081 端口）
        ├ 改写入站 Host/Origin 为 127.0.0.1:dshPort → 绕过浏览器信任栅栏
        ├ 网页内 8 位 PIN 认证（App 不参与）
        └ 可选 cloudflared 公网隧道
                    ▼
        DeepSeek Harness web（127.0.0.1:3080）
```

## 3. 模块划分

| 模块 | 职责 | 关键点 |
| --- | --- | --- |
| EntryAbility | 生命周期、窗口 | 保持默认窗口（v1.0 不做沉浸式） |
| pages/Index | 连接入口 | ScanKit 默认扫码界面；权限申请（CAMERA）；历史列表 |
| pages/WebShell | ArkWeb 套壳 | 自适应单/双栏；错误页；进度条；Web 内后退 |
| pages/SettingsPage | 管理 | 历史/Web 数据清理；版本信息（bundleManager） |
| common/utils/UrlUtils | URL 校验规范化 | 纯函数，可单测；放行 http(s)，拒绝其余协议 |
| common/store/ConnectionStore | 历史持久化 | Preferences JSON 数组，上限 20 条，LRU 排序 |
| model/ConnectionProfile | 连接模型 | 序列化契约 {url,title,addedAt,lastUsedAt} |

## 4. 关键设计决策

1. **扫码用 ScanKit 系统默认界面**（scanBarcode.startScanForResult）：免自绘相机 UI，支持相册识码，API 10+ 稳定。只需 CAMERA 权限（user_grant，需运行时申请）。
2. **WebShell 自适应**：onAreaChange 监听窗口宽度，>=840vp 切双栏（侧栏 + Web）。折叠屏展开/平板横屏自动生效，Web 组件不销毁重建。
3. **明文 http 放行**：局域网 dsh-pocket 为 http，ArkWeb 默认允许，无需网络安全配置。
4. **PIN 不落盘**：认证发生在网页会话内；App 只存 URL（连接历史），清理时提供 Web 数据清空入口。
5. **单模块单入口**：v1.0 保持 entry 单模块，不拆 HAR；后续如需独立功能再拆。
6. **测试策略**：纯逻辑（utils/model）Hypium 单测；UI 冒烟（ohosTest + uitest dumpLayout）；真机 smoke 脚本；CI 只构建不跑设备测试（无设备 runner）。

## 5. 鸿蒙系统特性利用（v1.0 落地 + 后续规划）

v1.0 已落地：
- ScanKit 系统扫码（默认界面 + 相册）
- 窗口宽度自适应（折叠屏/平板双栏）
- Preferences 本地持久化
- 系统 Web（ArkWeb）引擎，WebSocket 全支持（DSH 审批弹窗/实时事件可用）

规划中（v1.1+，按需推进）：
- **服务卡片（Widget）**：一键直达最近连接，无需进 App
- **Share Kit**：把连接地址分享到其他设备
- **窗口沉浸式 + 内容安全区适配**：Web 顶部不被状态栏遮挡
- **深色模式跟随**：系统深色时 WebShell 外壳同步
- **横屏适配**：手机横屏也启用双栏
- **应用内更新**：自用分发不便，考虑从 GitHub Release 拉取新 HAP 自更新
- **断线自动重连**：Web 层心跳检测 + 自动 refresh

## 6. 测试与质量

| 层 | 手段 | 执行位置 |
| --- | --- | --- |
| 单元测试 | Hypium（UrlUtils / ConnectionProfile） | 真机/模拟器 |
| UI 冒烟 | ohosTest：启动 → 断言首页元素 | 真机/模拟器 |
| 真机冒烟 | scripts/smoke.sh：装/启/查布局/查日志/卸 | 真机（hdc） |
| 构建校验 | GitHub Actions：assembleHap | CI（Docker 镜像） |

## 7. 构建、签名与分发

- 本地构建：scripts/build.sh（探测 DevEco 工具链；环境变量可覆盖）
- 签名：自用场景，DevEco 登录华为账号自动签名最省事；CI 签名走 repository secrets + hap-sign-tool.jar
- 分发：自用 HAP 直接安装（`hdc install -r` 或手机本地安装）；GitHub Release 作为备份分发通道
- 目标系统：HarmonyOS 7.0.1（手机，API 25），targetSdkVersion = 7.0.1(25)，compatibleSdkVersion = 6.0.0(20)

## 8. 已确认事项（2026-08-23 用户答复）

1. ✅ 手机系统：HarmonyOS 7.0.1（API 25）→ targetSdkVersion = 7.0.1(25)
2. ⏳ DevEco Studio：用户自行安装，装好后探测并验证构建
3. ✅ bundleName：com.dsh.lite
4. ⏳ GitHub 仓库：尚未创建（workflow 与仓库无关，建仓后 git remote add 即可）
5. ✅ 测试设备：普通直板手机（7.0.1）；折叠屏/平板双栏逻辑以断点模拟验证，后续真机补测
6. ⏳ 华为账号：未确认，默认走本地调试签名；装好 DevEco 后可自动签名
