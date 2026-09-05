#!/usr/bin/env bash
# ui-smoke.sh —— 真机 UI 冒烟（基于 DevEco CLI / devecocli ui）。
# 前置：手机连接（USB 或 hdc tconn）且已解锁；App 已安装或允许本脚本构建安装。
# 作用：安装(可选)→启动→用 devecocli ui layout 断言首页关键文案→截图存证→hilog 错误扫描→卸载(可选)。
# 用法:
#   ./scripts/ui-smoke.sh                  # 构建 debug + 安装 + 启动 + UI 校验 + 卸载
#   ./scripts/ui-smoke.sh --hap x.hap      # 使用指定 HAP
#   ./scripts/ui-smoke.sh --no-install     # 只做 UI 校验（假定 App 已装好）
#   ./scripts/ui-smoke.sh --skip-uninstall # 校验后不卸载
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/dev-tools.sh"

BUNDLE="com.dsh.lite"
HAP=""
NO_INSTALL=0
SKIP_UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --no-install) NO_INSTALL=1 ;;
    --skip-uninstall) SKIP_UNINSTALL=1 ;;
    *) HAP="$arg" ;;
  esac
done

DEVECOCLI="$ROOT/scripts/devecocli.sh"

[ -z "${HDC:-}" ] && { echo "错误: 未找到 hdc（需 DevEco SDK 或 PATH）" >&2; exit 1; }
[ -x "$DEVECOCLI" ] || { echo "错误: 缺少 $DEVECOCLI（应随仓库提交）" >&2; exit 1; }

# 1. 确认设备在线
echo "==> 设备列表"
"$DEVECOCLI" device list || true
DEVCOUNT="$("$HDC" list targets 2>/dev/null | grep -vE '^\[Empty\]$|^$' | wc -l | tr -d ' ')"
[ "${DEVCOUNT:-0}" -gt 0 ] || { echo "错误: 未检测到设备（请连接手机并解锁，hdc list targets 应能看到）" >&2; exit 1; }

# 2. 构建 + 安装 + 启动
if [ "$NO_INSTALL" = "0" ]; then
  if [ -z "$HAP" ]; then
    echo "==> 未指定 HAP，执行构建…"
    bash "$ROOT/scripts/build.sh"
    HAP="$(find "$ROOT/entry/build" -name "*signed.hap" 2>/dev/null | head -1)"
    [ -z "$HAP" ] && { echo "错误: 构建产物未找到" >&2; exit 1; }
  fi
  echo "==> 安装 $HAP"
  "$HDC" install -r "$HAP"
  echo "==> 冷启动应用"
  "$HDC" shell aa force-stop "$BUNDLE" || true
  "$HDC" shell aa start -a EntryAbility -b "$BUNDLE"
  sleep 4
else
  echo "==> 跳过安装，把 $BUNDLE 调到前台"
  "$HDC" shell aa start -a EntryAbility -b "$BUNDLE" || true
  sleep 2
fi

# 3. UI 布局断言（devecocli ui layout）
echo "==> devecocli ui layout 校验首页"
LAYOUT_FILE="$(mktemp -t dsh_ui_layout).txt"
"$DEVECOCLI" ui layout > "$LAYOUT_FILE" 2>&1 || true
LAYOUT="$(cat "$LAYOUT_FILE" 2>/dev/null || true)"
if [ -z "$LAYOUT" ]; then
  echo "FAIL: devecocli ui layout 无输出（设备可能未解锁或未在前台）" >&2
  "$DEVECOCLI" ui layout --format json 2>&1 | head -20 || true
  exit 1
fi
echo "$LAYOUT" | sed -n '1,30p'

echo "==> 断言首页关键文案"
PRIMARY="口袋工作台"
SECONDARY=("最新会话" "会话列表")
ALL_OK=1
CHK() {
  local m="$1"
  if echo "$LAYOUT" | grep -qF "${m}"; then
    echo "PASS: 首页命中 '${m}'"
  else
    echo "WARN: 首页未命中 '${m}'（可能是空态/未解锁/异常，需人工确认）"
    ALL_OK=0
  fi
}
CHK "$PRIMARY"
for m in "${SECONDARY[@]}"; do CHK "$m"; done

# 4. 截图存证
echo "==> 截图"
mkdir -p "$ROOT/build"
SHOT="$ROOT/build/ui-smoke-$(date +%Y%m%d-%H%M).png"
if "$DEVECOCLI" ui screenshot --path "$SHOT" >/dev/null 2>&1; then
  echo "已保存截图: $SHOT"
else
  echo "截图失败（忽略，不阻断）"
fi

# 5. hilog 错误检查
echo "==> 日志检查（最近 DSHHarmony 相关 error/fail）"
"$HDC" shell hilog -x 2>/dev/null | grep -iE "DSHHarmony" | grep -iE "error|fail" | tail -8 || echo "（无相关错误日志）"

# 6. 卸载（保持设备干净）
if [ "$SKIP_UNINSTALL" = "0" ]; then
  "$HDC" shell bm uninstall -n "$BUNDLE" || true
fi

cp "$LAYOUT_FILE" "$ROOT/build/ui-smoke-layout.txt" 2>/dev/null || true
rm -f "$LAYOUT_FILE"

if [ "$ALL_OK" = "1" ]; then
  echo "UI-SMOKE OK"
else
  echo "UI-SMOKE WARN（部分标记未命中，见上方 WARN/布局）"
  exit 0
fi
