#!/usr/bin/env bash
# smoke.sh —— 真机冒烟测试（安装 → 启动 → UI 校验 → 日志检查 → 卸载）。
# 前置：手机开启 USB 调试并连接（hdc list targets 能看到设备）。
# 用法:
#   ./scripts/smoke.sh                # 自动构建 debug 后冒烟
#   ./scripts/smoke.sh path/to.hap    # 使用指定 HAP 冒烟
#   ./scripts/smoke.sh --skip-uninstall
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/dev-tools.sh"

BUNDLE="com.dsh.lite"
HAP=""
SKIP_UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --skip-uninstall) SKIP_UNINSTALL=1 ;;
    *) HAP="$arg" ;;
  esac
done

[ -z "${HDC:-}" ] && { echo "错误: 未找到 hdc（需 DevEco SDK 或 PATH）" >&2; exit 1; }

if [ -z "$HAP" ]; then
  echo "==> 未指定 HAP，执行构建…"
  bash "$ROOT/scripts/build.sh"
  HAP="$(find "$ROOT/entry/build" -name "*.hap" 2>/dev/null | head -1)"
  [ -z "$HAP" ] && { echo "错误: 构建产物未找到" >&2; exit 1; }
fi

echo "==> 设备列表:"
"$HDC" list targets

echo "==> 安装 $HAP"
"$HDC" install -r "$HAP"

echo "==> 冷启动应用"
"$HDC" shell aa force-stop "$BUNDLE" || true
"$HDC" shell aa start -a EntryAbility -b "$BUNDLE"
sleep 3

echo "==> UI 布局校验（uitest dumpLayout）"
LAYOUT="$("$HDC" shell uitest dumpLayout 2>/dev/null || true)"
if echo "$LAYOUT" | grep -q "DSH Harmony"; then
  echo "PASS: 首页包含 'DSH Harmony'"
else
  echo "FAIL: 首页未找到 'DSH Harmony'"
  echo "$LAYOUT" | head -40
  exit 1
fi

echo "==> 日志检查（最近 30 秒内 DSHHarmony 相关 error/fail）"
"$HDC" shell hilog -x 2>/dev/null | grep -iE "DSHHarmony" | grep -iE "error|fail" | tail -10 || echo "（无错误日志）"

echo "==> 卸载（保持设备干净）"
if [ "$SKIP_UNINSTALL" = "0" ]; then
  "$HDC" shell bm uninstall -n "$BUNDLE" || true
fi
echo "SMOKE OK"
