# Changelog

## 2026-08-30

### feat
- **会话详情页全面增强**（原生详情页，替代只进 WebShell 的单一入口）：
  - 「对话」展示真实消息：仅取 `user/message`(输入框原文) 与 `assistant/message`，排除 tool / assistant/chunk 噪音；修复用户消息体直接位于 `data` 上导致漏读的问题
  - **Markdown 渲染**：新增 `common/utils/Markdown.ets` 解析器 + `components/MarkdownText.ets` 渲染组件，支持标题 / 段落 / 代码块 / 列表 / 引用 / 分隔线及行内 **加粗** *斜体* `代码` [链接]；行内代码与代码块**跟随深浅色**
  - **消息图片显示**：消息含 image 块时用 `session.attachment` 拉取 base64 → PixelMap，气泡内 140×140 缩略图（新增 `fetchSessionAttachment` / `SessionImage` / `AttachmentResult`）
  - **发送带图**：输入框左侧相机按钮，相册多选(≤9)统一转 JPEG(80) → base64；缩略图左对齐 + 横向滚动、逐张 ✕ 移除；支持纯图 / 图文混合
  - 进入停在顶部、发送后滚到底；实时刷新「内容变化才重建 + 停在底部才自动跟随」（`MessageDataSource` LazyForEach 数据源 + 内容签名比对 + nearBottom）
  - 「思考中…」提示（会话 running 时）
  - AI / 用户消息气泡不同底色（新增 `user_bubble_background`，base / dark）
  - 键盘避让 RESIZE：弹键盘不遮挡状态栏
  - 网络切换：详情页跟随共享 `activeConnUrl` 换地址、重连 WebSocket、并**失败时不清空已有消息**
- **首页重排**：改为两张卡片「最新会话」(点击直达**会话详情页**) + 「会话列表」(点击进任务列表)；右上角 [扫码(取景框+横线)][设置]；移除底部大按钮 / 连接卡片 / 空态（手动输入地址移到设置页）
- **连接自动切换**：解析出可用连接（局域网直连 → 公网隧道），网络监听(connection) + 手动 / 周期探测；都不通则首页常驻提示、无可用地址时弹窗引导添加
- 「自动连接最近的 IP」→「**自动启动控制台**」（用解析出的可用连接自动进入控制台）
- **服务卡片点击 → 原生会话详情页**（该连接最新会话），打不开则留首页（不再进 WebShell）
- 任务列表移除每张会话卡片上的控制按钮（暂停/继续/停止/完成保留在详情页）
- 设置页新增「输入电脑端地址」入口（复用手动输入连接地址对话框）
- **通知增强**（push-notify）：①通知点击**直达对应会话详情页**（推送 `data` 带 `sessionId + dshUrl`，App 解析后进原生详情页）②文案/去重：会话结束带目标、per-session 冷却 + 问题/批准按 id 去重 ③稳定性：JWT 鉴权失败强制刷新、无效 token 清理、`/api/status` 增加 `queued/uptime/lastPoll`
- **移除『长时间无响应』推送**：仅保留「会话结束 + 需信息/需批准」两场景
- **通知开关**：设置页新增「通知」分组——「启用推送(总开关)」「会话结束提醒」，App 通过 `/api/push.settings` 下发到电脑端推送器(持久化 settings.json)，总开关关则不上报 token

### fix
- 会话详情页拉取历史失败时不再清空对话
- 行内代码 / 代码块夜间版配色（白底蓝字 → 深底柔青蓝）
- 弹键盘不再遮挡状态栏（`KeyboardAvoidMode.RESIZE`）
- 移除任务列表卡片按钮后清理未使用代码 / 导入

### refactor
- `PocketApi.promptSession` 改为接受内容数组（文本 + 图片），`PromptContentPart` 支持图片字段
- `LatestSessionInfo` 补充 `sessionId / phase / objective`（供详情页直达）
- 消息列表改用 `MessageDataSource`（`IDataSource` LazyForEach）提升滚动流畅度
- 首页连接探测统一：`resolveConnection` / `checkReachable`，`activeConnUrl` 用 `@StorageLink` 与各页共享

## 2026-08-25

### feat
- **Push Kit 推送全链路打通**（华为 AGC）：
  - 消息类别权益「工作事项提醒」审核通过 → 发送 category=WORK（营销类必须 MARKETING，未获批不可冒充服务/通讯类）
  - HarmonyOS NEXT 使用 **V3 场景化 API**（V1/V2 仅支持 3.x/4.x）：`POST /v3/<projectId>/messages:send` + `push-type: 0`，鉴权改为**服务账号密钥 → PS256 JWT**（API Console 下载）
  - 调试证书闭环：AGC 只接受 ECDSA CSR（keytool EC prime256v1），新证书配私钥后重签装机，token 重新有效
  - push-notify 华为通道重写（V3+JWT），launchd 常驻服务 SENDER=huawei；重装/首连即上报 token（Index.openUrl）
  - 新装首启请求通知权限（notificationManager.requestEnableNotification）
  - 修复 JWT PS256 padding 常量（RSA_PKCS1 → RSA_PKCS1_PSS）导致 80200001
- **全局沉浸式状态栏**：所有页面 expandSafeArea + 状态栏留白；深色判定改用 ResourceManager（冷启动 config.colorMode 不可靠）；启动窗口背景 dark 变体修复冷启动白屏；WebShell 关 forceDarkAccess + 轮询网页 body 亮度跟随网页主题
- **扫码统一系统**：删除 ScanPage，首页扫码直接 scanBarcode.startScanForResult（修复 6.1 uiMaterial 崩溃）

### refactor
- 签名体系：新增 product `local`（unsigned 构建）+ `scripts/sign-local.mjs` 手动签名流水线（绕开 hvigor 加密密码 material 体系）；`scripts/encrypt-pwd.mjs` 生成 material 密文，default product 恢复 DevEco 直接构建
- 删除 test 测试推送通道，仅保留 huawei

### fix
- 冷启动深色模式状态栏/启动窗口白屏（material N/A 资源 + 时序兜底）
- WebShell 网页内切换浅/深色被 forceDarkAccess 覆盖

## 2026-08-24

### feat
- **WebShell 跟随系统深浅色自动切换**：Web.darkMode(Auto) + forceDarkAccess（DSH 网页随手机深/浅色实时变换主题；网页无深色适配时强制变暗兜底）；onConfigurationUpdate 同步 osThemeIsDark 到 AppStorage
- **系统栏同步深浅色**：WebShell 系统栏改为跟随主题（深色→深底白字，浅色→浅底黑字），@StorageLink('osThemeIsDark') + @Watch 切换瞬间即时刷新（此前写死白底黑字，深色下状态栏不协调）
- 相册图片注入输入框：右下悬浮「图片」按钮（官方 systemMaterial 沉浸光感，ULTRA_THIN）→ 系统相册选择器 → ImageKit 统一转 JPEG(quality 80，兼容 HEIC/PNG/WebP，满足 DSH 单张 ≤20M) → runJavaScript 构造 File + 合成 drop 事件 → DSH 原生 onDrop 接收为图片附件（无需附件按钮）
- Push Kit 方案推进（统一数据源/系统级推送，进行中）：
  - 手机端 PushToken.ets：pushService.getToken() 获取设备推送令牌 + 上报电脑端（已接入 EntryAbility onCreate，编译通过）
  - 电脑端独立推送服务 tools/push-notify/push-notify.js（Node 零依赖）：收 Token（POST /api/push.token:3082）+ 轮询 session.list + 推送发送端支持双通道（SENDER 切换：test=临时异常测试渠道 / huawei=华为自有 REST API oauth2/v3/token + messages:send）
  - **推送链路经临时异常测试渠道实测打通**（维护工具，非对外功能）：修复 dsh-pocket 登录（表单 token 字段）
  - **推送策略重构（仅三场景推送）**：① 会话结束 → 汇报（完成/已结束 + 目标 + 轮步统计）② 长时间无响应（updatedAt 停滞 >90s 且连续 >5 次）→ ⏰ 提醒 ③ 会话中途收集信息（events.mux 事件流，打开即回放 pending question + 实时）→ 📩 推送；其余状态一律不推；发送串行队列 + 3.1s 节流（规避测试渠道限流 429）；多会话跟踪（不再只盯最新会话）
  - AGC 集成就绪：agconnect-services.json 已入工程；AppID 认证测试通过（客户端密钥 OAuth 换 access_token 成功）（access_token 获取成功）
  - 文档 docs/push-plan.md 细化实现与待办

### ci
- 自托管 GitHub Actions runner（Mac）根治工具链下载问题：push 即完整构建（本机工具链零下载、秒级）；此前尝试 cache/并行下载/zstd 单文件均受 GitHub runner 大文件下载限制（3.5G 分卷/1.96GiB 单文件 30+ 分钟仍失败）
- push/PR 轻量 verify（秒绿）；完整构建走 self-hosted；tag 发布完整构建+签名
- CI 不再做签名发布（release job 移除）：GitHub Release 产物走本地上传（不签名包）；发布证书签名材料与 scripts/sign-release.sh 保留本地备用
- 分卷发布 v0.1.1-tools → v0.1.2-tools（1.96GiB 单文件 .tar.zst）经验保留在 Release

### chore
- 回退「任务监听（通知实时进度）」全套（cac7933）：实况窗/保活受平台权益与限制不可用，改为 Push Kit 方案推进

## 2026-08-23

### feat
- 连接历史页（HistoryPage）：按 IP 去重、时间倒序、左滑删除、点击直达；首页仅显示最近一条连接
- 设置页：「自动扫描局域网」开关改为「自动连接最近的 IP」（进入 App 自动连最新历史地址）；扫描局域网入口移至设置页（结果卡片列表展示）
- 品牌图标：App 图标换为 DeepSeek 官方黑色 logo + 白色背景；服务卡片（小组件）鲸鱼由 emoji 换成官方蓝色 logo（透明背景）；首页设置按钮改为齿轮图标；首页连接卡片禁用长按删除（删除仅历史页左滑）
- 自绘扫码页（替换系统默认界面）：状态栏真透明 + 全屏相机 + 直角取景框 + 微信式绿色渐变扫描条（PNG 素材，往复动效）+ 沉浸光感圆钮（systemMaterial；❌ 取消 / 🔦 手电筒 customScan 闪光灯，图标随深浅色主题）
- 启动图：鲸鱼娘 Q 版动漫形象（白底，来源 fornarwhal/deepseek-whale-girl-icon，CC BY-NC-SA 4.0）
- 网页导出会话日志自动保存到系统下载目录（picker DOWNLOAD 模式：零弹窗、持久化授权 URI，落在 下载/<包名>/）
- 首页新增「最新会话」卡片（标题/进行中/轮次/步骤/相对时间，点击刷新）；服务卡片（桌面小组件）同样展示最新会话（标题自动换行 + 状态两行）
- 设置页新增「局域网 PIN」配置项（默认 11111111，dsh-pocket 自定义 PIN 可同步修改）
- 服务卡片（ConnectionCard）升级：连接状态 + 最近使用时间；新增沉浸式返回按钮 BackButton 与统一系统栏 WindowBar

### fix
- 自动扫描开关失效（无论开/关每次显示首页都会扫描）：开关配置异步读取与 onPageShow 竞态，默认值 true 提前参与判定 → 改为配置读取完成后再判定（autoScanReady + maybeAutoScan）
- 下载链路多轮排障：request 下载服务在 ArkWeb 回调内 Native 崩溃 → 权限弹窗静默挂起 → 改手动 HTTP（带 Web Cookie）→ DOWNLOAD 模式公共目录直写（沙箱兜底）
- 服务卡片与 Form 扩展接入最新会话查询（复用 App 保存的访问令牌；无令牌/失败回退原布局）

### ci
- 安装包只在 tag(v*) 节点产出：push/PR 仅构建验证不再上传 debug 包，正式安装包经 GitHub Release 发布

### docs
- 排查记录 dsh-pocket「文件浏览」依赖宿主缺失的 aionui explorer 列（上游 issue #48，已提交）

### feat
- 项目脚手架：基于 Empty Ability 模板初始化 DSH Harmony 工程（com.dsh.lite）
- 首页：连接历史列表 + 扫码连接（ScanKit 系统默认界面）+ 手动输入地址
- WebShell：ArkWeb 套壳页，加载 dsh-pocket 网页，窄屏/宽屏（折叠屏展开、平板）自适应双栏布局
- 设置页：连接历史管理、Web 数据清理、关于信息
- 测试：Hypium 单元测试（URL 工具、连接模型）+ ohosTest UI 冒烟测试
- 工具链：scripts 构建/冒烟/测试/changelog 脚本
- CI：GitHub Actions 构建 workflow + 签名发布流程
- 本地技能：.agents/skills/harmony-dev（编码规范、Review 规范，不对外）

### chore
- bundleName 定为 com.dsh.lite；targetSdkVersion 升至 7.0.1(25)（用户确认系统为 HarmonyOS 7.0.1 / API 25）

### fix
- WebStorage.deleteAllData 为同步 API，去除 .then()；WebCookieManager 静态类改用 clearAllCookiesSync
- 删除未使用 import；修正单元测试相对导入路径；ohosTest 补齐 pages/Index 占位页

### ci
- CI 改用华为官方 command-line-tools（CLT_URL 直链），弃用第三方容器镜像（匿名拉取被拒）

### fix
- 首轮实编译修复（DevEco 6.1.1 / SDK 24）：Web 事件类型与 OverScrollMode 改为全局类型；TestRunner 按官方模板重写（AbilityMonitor + startAbility）；Hypium 断言改用基础集；ArkTS 正则改 RegExp 构造器；targetSdkVersion 调整为本机 SDK 24
- ohosTest/单测模块补齐 schema 字段（startWindowBackground 等），测试包构建通过

### test
- 单元测试 15 个用例全部通过（UrlUtils 11 + ConnectionProfile 4），行覆盖率 74% / 分支 87.5%

### chore
- 推送 GitHub（enoughpower/dsh-harmony，分支 master）；新增 MIT LICENSE；SIGNING.md 签名指引；release 构建验证通过

### ci
- 修复 workflow 顶层 env 引用 runner.temp 导致 run 即失败的问题（移到 step env）；actionlint 本地校验通过；CI 链路验证：触发→checkout→工具链安装（CLT_URL 配置后全通）

### fix
- WebShell 不再拦截 HTTP 状态码（dsh-pocket PIN 页的子资源 401 曾触发错误覆盖层）；只拦截网络级错误
- smoke.sh dumpLayout 改为 -p 存文件再 cat（原写法捕获不到布局内容）

### test
- 真机全链路验证通过（Pura 80 Pro / 7.0.0 / API 26）：签名构建 → 安装 → 首页 → 输入地址 → WebShell → dsh-pocket PIN 认证 → DSH 主界面可用（发送/模型/工作区）

### ci
- **CI 全绿**：工具包经 GitHub Release 分发（v0.1.0-tools，CLT_URL 变量），修复 DEVECO_SDK_HOME 后云端完整构建通过（下载→install→assembleHap→artifact）
- workflow 支持 tag v* 触发 release 流程；actionlint 本地校验

### fix
- 窗口系统栏自定义彻底移除：全屏重叠、非全屏透明系统栏黑边两个问题均已回退（窗口恢复系统默认，深色由 dark 资源适配）
- 自动发现补 ohos.permission.GET_NETWORK_INFO 权限（getDefaultNet 被拒导致扫描失败）

### feat
- **v1.2 局域网自动发现**：扫描本机网段 3081 端口识别 dsh-pocket，免扫码/免输 IP（电脑 IP 漂移场景实测命中），单服务自动直达，多服务列表选择
- 首页新增"自动发现局域网 DSH（免扫码）"入口与扫描进度、结果卡片
- **打开即自动扫描**：冷启动自动发现并直达（会话内一次，返回首页不重复扫）；设置页新增开关（AppPrefs 持久化）
- **服务卡片信息增强**：在线/离线状态（弱探测 3081）+ 最近使用相对时间；打开首页自动刷新卡片状态

### docs
- README / README.en 双语说明
- docs/architecture.md 架构设计

---
