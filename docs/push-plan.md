# DSH Harmony 任务进度推送方案（Push Kit）

> 状态：**方案推进中**（2026-08-24，代码已就绪，待 AGC 凭证）
> 目标：手机 App 在**后台/被杀**时也能收到 DSH 任务进度通知（开始/进度/完成）
>
> ### 已完成（代码就绪，未提交）
> - 手机端：`entry/.../common/store/PushToken.ets` —— `pushService.getToken()` 取 token + POST 上报电脑端（已接入 EntryAbility.onCreate，编译通过）
> - 电脑端：`tools/push-notify/push-notify.js` —— 收 token + 轮询 session.list + 调华为 Push API（Node 内置 fetch，无额外依赖）
> - 方案：B（独立推送服务，不改 dsh-pocket）
>
> ### 待办（需用户）
> 1. 华为 AGC 注册 → 创建应用（bundleName: com.dsh.lite）→ 开通推送服务
> 2. 拿 AppID / AppSecret → 设环境变量 `PUSH_APP_ID` / `PUSH_APP_SECRET`
> 3. 启动电脑端 `node tools/push-notify/push-notify.js`，手机 App 开机后自动上报 token

## 1. 背景与问题

- App 现有"任务监听"已回退（后台保活不可靠：DATA_TRANSFER 长时任务被系统判假冻结；实况窗需华为侧权益，个人账号不可用；ServiceExtension 手机不支持）
- 现状能力：前台轮询+通知 OK；后台会冻结，回前台自动恢复
- 结论：**纯 App 侧无法可靠后台推送，需系统级通道（Push Kit）**

## 2. 方案对比（已评估）

| 方案 | 后台可靠 | 成本 | 结论 |
|---|---|---|---|
| 前台轮询（现回退） | ❌ | 低 | 仅前台 |
| 长时任务 DATA_TRANSFER + 加密轮询 | ⚠️ 不保证 | 中 | 已试，不可靠 |
| 实况窗（LiveView） | — | 中 | 需华为"实况窗权益"，个人拿不到 |
| ServiceExtension/AppService | — | 中 | 手机不支持（AppService 仅 2in1） |
| **Push Kit（华为系统推送）** | ✅ 强杀也能收 | 中 | **选定方向** |

## 3. Push Kit 架构

```
电脑端 dsh-pocket / 独立推送服务（监听 DSH 任务进度）
   │  任务开始/进度变化/完成 → 调华为 Push REST API
   ▼
华为推送服务（公网 push-api.cloud.huawei.com）
   │  系统级通道（应用进程存活无关）
   ▼
手机（HarmonyOS Push SDK）→ 通知栏显示 → 点击打开 App
```

## 4. 实施步骤

### 4.1 华为侧注册（需用户，免费，约 10 分钟）
1. 注册华为开发者账号
2. AGC 控制台创建应用（bundleName: com.dsh.lite）
3. 开通"推送服务（Push Kit）"
4. 获取：AppID、AppSecret（电脑端调用凭证）

### 4.2 手机端（App，改 dsh-harmony）
- 集成 @kit.PushKit（HarmonyOS 推送 SDK）
- 启动时获取 Push Token，通过 dsh-pocket 上报电脑端
- 系统自动接收通知；点击通知打开 App

### 4.3 电脑端推送触发（二选一）
- **A. 改 dsh-pocket**：在其监听会话状态变化处调华为 Push API（需维护升级）
- **B. 独立推送服务**：电脑常驻一个小服务，读 DSH session.list 变化 → 调华为 API（不动 dsh-pocket）

### 4.4 通知设计
- 标题：会话标题
- 文本：▶ 进行中 · N 轮 · M 步 / ■ 已完成
- 点击：打开 App
- **节流**：华为推送有频控，服务器端合并（如 30s 一条）

## 5. 关键决策点（待定）

| 项 | 选项 | 备注 |
|---|---|---|
| 推送逻辑位置 | A 改 dsh-pocket / B 独立服务 | B 不依赖三方，推荐 |
| Token 上报 | dsh-pocket 加接口 or 独立服务收 | 需定上报路径 |
| 频控节流 | 30s / 状态变化即时+进度节流 | 与 App 内通知策略一致 |

## 6. 风险与备选
- 华为账号/AGC 开通限制（个人一般可开通推送）
- 推送延迟：秒级，可接受
- 备选：若 AGC 不可用 → 局域网内自建推送（手机与电脑同网，App 后台保持短连接受限）→ 兜底仍是"前台实时"
