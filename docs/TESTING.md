# 测试与质量保障

DSH Harmony 的测试策略：**纯逻辑单测（设备上 Hypium）→ UI 冒烟（ohosTest）→ 真机冒烟（hdc 脚本）→ CI 构建校验**。HarmonyOS 单测必须在设备/模拟器上运行，因此测试分本地设备执行与 CI 构建校验两段。

## 1. 测试分层

| 层 | 位置 | 内容 | 执行 |
| --- | --- | --- | --- |
| 单元测试 | `entry/src/test/` | UrlUtils（URL 校验/规范化边界）、ConnectionProfile（序列化往返） | 真机/模拟器 |
| UI 冒烟 | `entry/src/ohosTest/` | 启动 EntryAbility → 断言首页出现 "DSH Harmony" | 真机/模拟器 |
| 真机冒烟 | `scripts/smoke.sh` | 安装 → 冷启动 → uitest dumpLayout 校验 → hilog 错误扫描 → 卸载 | 真机（hdc） |
| 构建校验 | GitHub Actions | ohpm install + assembleHap（debug/release） | CI（Docker 镜像） |

## 2. 本地执行

```bash
# 前置：DevEco 工具链可用（scripts/dev-tools.sh 探测），手机开 USB 调试

./scripts/build.sh --install   # 构建并安装
./scripts/smoke.sh             # 真机冒烟（自动构建）
./scripts/unit-test.sh         # 单测（hvigorw test；不支持时用 DevEco Test 运行配置）
```

命令行单测的 `aa test` 路径（测试包已构建安装后）：

```bash
hdc shell aa test -b com.dsh.lite -m entry_test -s unittest OpenHarmonyTestRunner
```

## 3. 编写新测试的规范

- **纯逻辑必须配单测**：新增 `common/utils/`、`model/` 功能时，在 `entry/src/test/test/` 下新建 `Xxx.test.ets`，并在 `List.test.ets` 中注册
- **导入主模块代码**：相对路径从 `src/test/test/` 出发，`../../main/ets/...`
- **UI 冒烟**：`entry/src/ohosTest/ets/test/`，用 `@kit.UiTestKit` 的 Driver/ON 定位；断言对象优先 `By.id()`（组件已带 id 时），否则 `ON.text()`
- **AAA 模式**：Arrange-Act-Assert；异步用例用 `async (done: Function)` 并在结束调用 `done()`

## 4. CI 与发布

- push/PR：debug 构建 + 产物 artifact（`.github/workflows/build.yml`）
- tag `v*`：release 构建 + secrets 签名 + GitHub Release
- CI 无真机：单测/冒烟不在 CI 跑；如需设备级 CI，可后续接自托管 runner + 鸿蒙设备（或 HVD 模拟器方案）

## 5. 已知边界

- `uitest dumpLayout` 的文本断言依赖布局快照，动态/异步渲染内容可能不在快照中——smoke 断言用静态文案（如 "DSH Harmony"）
- ArkWeb 页面内容（DSH webui）不做 UI 断言，Web 层正确性靠人工/真机冒烟验证
- API 25（HarmonyOS 7.0.1）为较新版本，若真机行为与文档有出入，以真机为准并在 skill 踩坑记录更新
