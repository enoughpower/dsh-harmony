#!/usr/bin/env bash
# dev-tools.sh —— 探测本机 HarmonyOS 工具链（DevEco Studio / SDK / hvigor / ohpm / hdc）。
# 供其他脚本 source 使用；也可直接运行打印结果。
# 用法:
#   source scripts/dev-tools.sh && "$HVIGORW" --version
# 环境变量可覆盖探测结果（CI 场景必须显式提供）：
#   DEVECO_HOME      DevEco Studio.app 目录（含 Contents/tools）
#   DEVECO_SDK_HOME  SDK 根目录（含 default/openharmony/toolchains/hdc）
#   HVIGORW          hvigorw 可执行文件
#   OHPM             ohpm 可执行文件
#   HDC              hdc 可执行文件
set -u

find_in_path() {
  command -v "$1" 2>/dev/null || true
}

# macOS: 从常见位置 + Spotlight 找 DevEco Studio
find_deveco_home() {
  if [ -n "${DEVECO_HOME:-}" ] && [ -x "$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw" ]; then
    echo "$DEVECO_HOME"; return
  fi
  for p in "/Applications/DevEco-Studio.app" "$HOME/Applications/DevEco-Studio.app"; do
    if [ -d "$p" ]; then echo "$p"; return; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    local hit
    hit=$(mdfind "kMDItemCFBundleIdentifier == 'com.huawei.devecostudio'" 2>/dev/null | head -1)
    [ -n "$hit" ] && echo "$hit" && return
    hit=$(mdfind "kMDItemFSName == 'DevEco-Studio.app'" 2>/dev/null | head -1)
    [ -n "$hit" ] && echo "$hit"
  fi
}

find_sdk_home() {
  if [ -n "${DEVECO_SDK_HOME:-}" ] && [ -x "$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc" ]; then
    echo "$DEVECO_SDK_HOME"; return
  fi
  local dc="${DEVECO_HOME:-}"
  if [ -n "$dc" ] && [ -d "$dc/Contents/sdk" ]; then echo "$dc/Contents/sdk"; return; fi
  for p in "$HOME/Library/OpenHarmony/Sdk" "$HOME/Library/Huawei/Sdk" "/Users/$USER/OpenHarmony/Sdk"; do
    [ -d "$p" ] && echo "$p" && return
  done
}

DEVECO_HOME="${DEVECO_HOME:-$(find_deveco_home)}"
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$(find_sdk_home)}"

# 逐个解析可执行文件（环境变量 > DevEco 内置 > PATH）
HVIGORW="${HVIGORW:-}"
if [ -z "$HVIGORW" ] && [ -n "$DEVECO_HOME" ] && [ -x "$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw" ]; then
  HVIGORW="$DEVECO_HOME/Contents/tools/hvigor/bin/hvigorw"
fi
[ -z "$HVIGORW" ] && HVIGORW=$(find_in_path hvigorw)

OHPM="${OHPM:-}"
if [ -z "$OHPM" ] && [ -n "$DEVECO_HOME" ] && [ -x "$DEVECO_HOME/Contents/tools/ohpm/bin/ohpm" ]; then
  OHPM="$DEVECO_HOME/Contents/tools/ohpm/bin/ohpm"
fi
[ -z "$OHPM" ] && OHPM=$(find_in_path ohpm)

HDC="${HDC:-}"
if [ -z "$HDC" ] && [ -n "$DEVECO_SDK_HOME" ] && [ -x "$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc" ]; then
  HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
fi
[ -z "$HDC" ] && HDC=$(find_in_path hdc)

export DEVECO_HOME DEVECO_SDK_HOME HVIGORW OHPM HDC

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "DEVECO_HOME=$DEVECO_HOME"
  echo "DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
  echo "HVIGORW=$HVIGORW"
  echo "OHPM=$OHPM"
  echo "HDC=$HDC"
  [ -z "$HVIGORW" ] && echo "提示: 未找到 hvigorw，请安装 DevEco Studio 或设置 HVIGORW 环境变量" >&2
fi
