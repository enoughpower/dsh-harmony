# 推送(Push Kit)合规与配置

## 消息类别权益(已获批)

- **权益名称**:工作事项提醒
- **category 值**:`WORK`
- **审核结果**:通过(2026-08-25)
- **作用**:App 自分类权益——`WORK` 类消息属于服务与通讯类,可单发、不受营销频次限制

## 发送消息时的 category 规范(强制)

| 消息类型 | category 取值 | 说明 |
| --- | --- | --- |
| 会话结束汇报 / 任务完成 / 异常提醒 / 需要信息 / 需要批准 | `WORK` | 本次审核通过的自分类权益,服务与通讯类 |
| 资讯 / 营销 / 推广类(目前无此场景) | `MARKETING` | 必须显式配置,受频次限制与用户授权约束,严禁冒充 WORK |

> ⚠️ **红线**:未审核通过的场景不可作为服务与通讯类消息推送。违规将面临**限制应用发送消息**等处罚。

## 代码落点

- **发送侧(电脑端)** `tools/push-notify/push-notify.js` → `huaweiSend()`:
  **V3 场景化 API**(HarmonyOS NEXT 5.x+ 必须,3.x/4.x 用 V2):
  `POST https://push-api.cloud.huawei.com/v3/<projectId>/messages:send` + Header `push-type: 0`
  鉴权:**服务账号密钥 → PS256 JWT**(API Console 下载 JSON,配 `PUSH_KEY_FILE`);
  载荷 `payload.notification = { title, body, category: 'WORK', clickAction: { actionType: 0 } }`,
  `target.token` 为数组。营销类消息必须换 `MARKETING`,不得复用 WORK。
- **服务账号密钥**:API Console → 创建"服务账号密钥"→ 下载 JSON(含 `project_id/key_id/sub_account/private_key`)。
  密钥文件与 `.env`/tokens 均不入库(已 gitignore)。
- **接收侧(App)** `entry/src/main/ets/common/store/PushToken.ets`:
  只负责 `pushService.getToken()` 并上报电脑端(`POST /api/push.token`),不涉及 category。

## 链路验证

1. 电脑端: `node --env-file=tools/push-notify/.env tools/push-notify/push-notify.js`(需 `SENDER=huawei` + AGC `PUSH_APP_ID/SECRET`)
2. App 端:启动时自动取 token 上报(电脑端 `tokens.json` 出现新 token 即成功)
3. 触发一次推送(任务结束/异常提醒)→ 手机通知栏应收到
4. hilog 检查:`getToken failed code=1000900012` 表示未开通(现已开通,不应再出现)

## 排查

- `1000900012`:推送未激活——确认 AGC 已开通推送服务、消息类别权益已获批
- `1000900010`:应用身份非法——确认 AGC 应用指纹/配置与签名一致
- 手机上收不到且无报错:确认电脑端 `SENDER=huawei`、`tokens.json` 非空、`/api/status` 正常