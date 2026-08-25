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

## 多设备调试（调试签名方案）

调试签名（Automatically generate signature）的 profile 绑定**允许调试的设备 UDID 列表**，默认只有自动签名时连接的那台手机。

**加新设备步骤**（换手机 / 加平板，普通账号支持多台）：

1. 新设备开启开发者模式 + USB 调试，连接电脑（会弹"允许 USB 调试"）
2. DevEco 打开工程 → `File > Project Structure > Signing Configs`
3. 重新点 **Automatically generate signature**（或 Sign In 后重新生成）→ DevEco 自动把新设备 UDID 加入 profile
4. 重新构建（`./scripts/build.sh`）→ 新的 HAP 即可在两台设备上安装

> 注意：**profile 变了要重装**——旧设备的旧安装包不需要重装（认证在安装时校验）；新设备装新版包即可。

## 常见问题

- **时间不一致**：本地系统时间必须与北京时间同步，否则签名校验失败
- **包名冲突**：自动签名关联 AGC 应用时若包名已被其他团队占用会报错——本工程用 `com.dsh.lite`，自用无冲突风险
- **升级换签名**：换签名后需先卸载旧版再安装（自用场景可接受）


## 两套打包配置(装机 / 上架)

工程 `build-profile.json5` 用**两个 product** 承载两套签名(该文件被 git 标记
skip-worktree,永不入库):

| product | signingConfig | 材料 | 用途 | hdc 侧载 |
| --- | --- | --- | --- | --- |
| `default` | `default` | DevEco 自动签名 `~/.ohos/config/default_dsh-harmony_*.p12/.cer/.p7b` | 装机/日常调试 | ✅ 可安装到手机 |
| `release` | `release` | 发布证书 `~/.ohos/config/dsh-release.p12 + release.cer + release-profile.p7b` | 平台/应用市场上架 | ❌ 系统拒绝(9568322) |

**重要:release 签名包不允许 hdc 侧载** —— HarmonyOS 硬性安全策略,发布证书产物只能走平台
审核分发。所以"装到手机上看"必须选 `default` product。

**切换方式**:
- **DevEco**: 构建/运行配置中选择 product(`default` = 装机, `release` = 上架);
  或 `File > Project Structure > Signing Configs` 查看/修改各 product 的签名
- **CLI**: `./scripts/switch-signing.sh build default debug`(装机) /
  `./scripts/switch-signing.sh build release release`(上架,注意产物的 .hap 不可 hdc 侧载)

**debug(自动签名)材料缺失时的处理**: debug 的 `.p7b` profile 只能由 DevEco 通过华为账号
在线生成(profile 绑定手机 UDID),离线 CLI 无法凭空生成。若 `~/.ohos/config` 下缺 debug profile:
1. DevEco 打开工程 → `File > Project Structure > Signing Configs`
2. 选 `Automatically generate signature`(需登录华为账号, 手机已连接)
3. 保存后 DevEco 会把 debug 的 `storePassword/keyPassword/profile` 补全进 build-profile.json5
4. 再 `./scripts/switch-signing.sh build default debug` 构建即得可侧载包

## 常见问题

- **时间不一致**：本地系统时间必须与北京时间同步，否则签名校验失败
- **包名冲突**：自动签名关联 AGC 应用时若包名已被其他团队占用会报错——本工程用 `com.dsh.lite`，自用无冲突风险
- **升级换签名**：换签名后需先卸载旧版再安装（自用场景可接受）


## 两套签名配置(debug 装机 / release 上架)

工程 `build-profile.json5` 的 `signingConfigs` 里维护**两套**签名(该文件被 git 标记
skip-worktree,永不入库):

| 名称 | 材料 | 用途 | hdc 侧载 |
| --- | --- | --- | --- |
| `debug` | DevEco 自动签名 `~/.ohos/config/default_dsh-harmony_*.p12/.cer/.p7b` | 装机/日常调试 | ✅ 可安装到手机 |
| `release` | 发布证书 `~/.ohos/config/dsh-release.p12 + release.cer + release-profile.p7b` | 平台/应用市场上架 | ❌ 系统拒绝(9568322) |

**重要:release 签名包不允许 hdc 侧载** —— HarmonyOS 硬性安全策略,发布证书产物只能走平台
审核分发。所以"装到手机上看"必须用 `debug` 签名构建。

切换方式: `./scripts/switch-signing.sh debug|release`(只切 product 的 signingConfig 引用)。

**debug 材料缺失时的处理**: debug 的 `.p7b` profile 只能由 DevEco 通过华为账号在线生成
(profile 绑定手机 UDID),离线 CLI 无法凭空生成。若 `~/.ohos/config` 下缺 debug profile:
1. DevEco 打开工程 → `File > Project Structure > Signing Configs`
2. 选 `Automatically generate signature`(需登录华为账号, 手机已连接)
3. 保存后 DevEco 会把 debug 的 `storePassword/keyPassword/profile` 补全进 build-profile.json5
4. 再 `./scripts/switch-signing.sh debug` 构建即得可侧载包
