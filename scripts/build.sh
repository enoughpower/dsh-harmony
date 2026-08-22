#!/usr/bin/env bash
# build.sh —— 命令行构建 DSH Harmony HAP。
# 用法:
#   ./scripts/build.sh            # 构建 debug HAP
#   ./scripts/build.sh release    # 构建 release HAP（无签名）
#   ./scripts/build.sh --install  # 构建并安装到已连接设备
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/dev-tools.sh
source "$ROOT/scripts/dev-tools.sh"

MODE="debug"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    release) MODE="release" ;;
    --install) INSTALL=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "${HVIGORW:-}" ]; then
  echo "错误: 未找到 hvigorw。请先安装 DevEco Studio 或设置 HVIGORW 环境变量。" >&2
  exit 1
fi

cd "$ROOT"
if [ -z "${OHPM:-}" ] || [ ! -x "$OHPM" ]; then
  echo "警告: 未找到 ohpm，跳过依赖安装（若 oh_modules 已存在可忽略）" >&2
else
  "$OHPM" install --all
fi

echo "==> hvigorw assembleHap ($MODE)"
"$HVIGORW" --mode module -p module=entry@default -p buildMode=$MODE assembleHap

HAP="$(find "$ROOT/entry/build" -name "entry-default.hap" -path "*outputs*" 2>/dev/null | head -1)"
if [ -z "$HAP" ]; then
  HAP="$(find "$ROOT/entry/build" -name "*.hap" 2>/dev/null | head -1)"
fi
echo "==> HAP: ${HAP:-(未找到，请检查构建输出)}"

if [ "$INSTALL" = "1" ] && [ -n "${HDC:-}" ] && [ -n "$HAP" ]; then
  echo "==> 安装到设备"
  "$HDC" install -r "$HAP"
  echo "==> 启动应用"
  "$HDC" shell aa start -a EntryAbility -b com.dsh.harmony
fi
