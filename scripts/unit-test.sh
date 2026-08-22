#!/usr/bin/env bash
# unit-test.sh —— 在真机上执行 Hypium 单元测试 + UI 冒烟测试。
# 说明：HarmonyOS 单测必须在设备/模拟器上运行。
#   DevEco 内运行：直接 Run 'entry' 的 Test 配置，等价且更省事。
#   命令行运行（需要先构建出测试包，命令因 hvigor 版本而异，见下）：
#     hvigorw --mode module -p module=entry@default test        # hvigor 直接支持时
#   aa test 参数（官方）：
#     hdc shell aa test -b com.dsh.lite -m entry_test -s unittest OpenHarmonyTestRunner
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/dev-tools.sh"

[ -z "${HDC:-}" ] && { echo "错误: 未找到 hdc" >&2; exit 1; }

# 1) 尝试 hvigor 的 test 任务（DevEco 5+/6 支持）
if [ -n "${HVIGORW:-}" ]; then
  echo "==> 尝试 hvigorw test"
  if "$HVIGORW" --mode module -p module=entry@default test --no-daemon 2>/dev/null; then
    echo "hvigorw test 完成"
  else
    echo "!! hvigorw test 未成功，请用 DevEco Studio 的 Test 运行配置执行单元测试" >&2
  fi
else
  echo "!! 未找到 hvigorw，请用 DevEco Studio 的 Test 运行配置执行单元测试" >&2
fi

echo
echo "==> 直接跑已安装测试包的替代路径（如测试包已构建安装）:"
echo "    hdc shell aa test -b com.dsh.lite -m entry_test -s unittest OpenHarmonyTestRunner"
echo "    hdc shell aa test -b com.dsh.lite -m entry_test -s unittest OpenHarmonyTestRunner -s class DSHHarmonySmoke"
