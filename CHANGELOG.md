# Changelog

## 2026-08-23

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

### docs
- README / README.en 双语说明
- docs/architecture.md 架构设计

---
