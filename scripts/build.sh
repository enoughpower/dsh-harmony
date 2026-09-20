#!/usr/bin/env bash
# build.sh —— 命令行构建 DSH Harmony HAP（自用 / 调试）。
# 上架包（AppGallery，含推送/AGC/权限裁剪）请用: ./scripts/build-store.sh
# 用法:
#   ./scripts/build.sh                      # 构建 debug HAP（product=default）
#   ./scripts/build.sh release              # release 构建优化（签名仍按产品 default）
#   ./scripts/build.sh --product release    # 指定 build-profile 产品（release=发布证书，禁 hdc 侧载）
#   ./scripts/build.sh --install            # 构建并安装到已连接设备
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/dev-tools.sh
source "$ROOT/scripts/dev-tools.sh"

MODE="debug"
PRODUCT="default"
INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    release) MODE="release" ;;
    debug) MODE="debug" ;;
    --product) PRODUCT="${2:?--product 需要参数}"; shift ;;
    --install) INSTALL=1 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
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

echo "==> hvigorw assembleHap (product=$PRODUCT, mode=$MODE)"
"$HVIGORW" --mode module -p module=entry@default -p product="$PRODUCT" -p buildMode="$MODE" assembleHap

HAP="$(find "$ROOT/entry/build" -name "entry-default-signed.hap" -path "*outputs*" 2>/dev/null | head -1)"
if [ -z "$HAP" ]; then
  HAP="$(find "$ROOT/entry/build" -name "entry-default.hap" -path "*outputs*" 2>/dev/null | head -1)"
fi
if [ -z "$HAP" ]; then
  HAP="$(find "$ROOT/entry/build" -name "*.hap" 2>/dev/null | head -1)"
fi
echo "==> HAP: ${HAP:-(未找到，请检查构建输出)}"

if [ "$INSTALL" = "1" ] && [ -n "${HDC:-}" ] && [ -n "$HAP" ]; then
  echo "==> 安装到设备"
  "$HDC" install -r "$HAP"
  echo "==> 启动应用"
  "$HDC" shell aa start -a EntryAbility -b com.dsh.lite
fi
