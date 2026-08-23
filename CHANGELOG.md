# Changelog

## 2026-08-23

### feat
- 网页导出会话日志自动保存到系统下载目录（picker DOWNLOAD 模式：零弹窗、持久化授权 URI，落在 下载/<包名>/）
- 首页新增「最新会话」卡片（标题/进行中/轮次/步骤/相对时间，点击刷新）；服务卡片（桌面小组件）同样展示最新会话（标题自动换行 + 状态两行）
- 设置页新增「局域网 PIN」配置项（默认 11111111，dsh-pocket 自定义 PIN 可同步修改）
- 服务卡片（ConnectionCard）升级：连接状态 + 最近使用时间；新增沉浸式返回按钮 BackButton 与统一系统栏 WindowBar

### fix
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
