# 应用签名指南

HarmonyOS 应用**必须签名才能安装到真机**。本工程为自用场景，推荐方案 A（最省事）。

## 方案 A：DevEco 自动签名（推荐）

前置：华为账号（手机号即可注册，https://developer.huawei.com）

1. 用 DevEco Studio 打开本工程（`dsh-harmony` 根目录）
2. 菜单 `File > Project Structure > Signing Configs`
3. 点击 **Sign In** 登录华为账号
4. 选择 **Automatically generate signature**（不关联 AGC 应用，适合自用不上架）
5. OK 保存 → DevEco 自动生成 `.p12` / `.cer` / `.p7b`，写入 `build-profile.json5` 的 `signingConfigs` 和 `local.properties`
6. 重新构建：`./scripts/build.sh`，产物变为已签名 HAP，可直接 `hdc install -r` 安装

> ⚠️ 签名文件与 `local.properties` 已被 .gitignore 排除，不会误提交。

## 方案 B：手动签名（无账号/离线场景）

1. DevEco：`Build > Generate Key and CSR`，生成 `.p12` 和 `.csr`（记录 alias 与密码）
2. 到 AGC 控制台申请调试证书（.cer）与 Profile（.p7b）——此步骤仍需华为账号
3. `File > Project Structure > Signing Configs` 取消自动签名，手动指定 `.p12` / `.cer` / `.p7b` 及密码
4. 构建后验证：`hdc install -r <hap>`

> 说明：HarmonyOS 没有 Android 式的通用 debug keystore，**任何签名路径都需要华为账号**（AGC 颁发证书/profile）。没有账号时无法安装到真机。

## CI 签名（GitHub Actions Release 用）

在仓库 Settings > Secrets and variables > Actions 配置：

| Secret | 值 |
| --- | --- |
| `SIGNING_KEY` | `.p12` 文件 base64（`base64 -i xxx.p12`） |
| `SIGNING_CERT` | `.cer` 文件 base64 |
| `SIGNING_PROFILE` | `.p7b` 文件 base64 |
| `KEYSTORE_PASSWORD` | p12 密码 |
| `KEY_PASSWORD` | key 密码 |
| `KEY_ALIAS` | key alias |

打 tag `v1.0.0` 推送后，release job 会自动签名并发布到 GitHub Release。

## 常见问题

- **时间不一致**：本地系统时间必须与北京时间同步，否则签名校验失败
- **包名冲突**：自动签名关联 AGC 应用时若包名已被其他团队占用会报错——本工程用 `com.dsh.lite`，自用无冲突风险
- **升级换签名**：换签名后需先卸载旧版再安装（自用场景可接受）
