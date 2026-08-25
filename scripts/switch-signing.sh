#!/usr/bin/env bash
# switch-signing.sh —— 切换打包配置 (product): 装机版 default / 上架版 release
# 用法:  ./scripts/switch-signing.sh show|build [default|release] [debug|release] [--install]
#
# 原理: build-profile.json5 里定义了两个 product, 各自绑定签名:
#   - product "default" → signingConfig "default" (DevEco 自动签名; 可 hdc 侧载装机)
#   - product "release" → signingConfig "release" (发布证书;   只能平台上架分发)
# DevEco 在构建/运行配置里选择 product 即切换打包配置; CLI 用 -p product=xxx。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BP="$ROOT/build-profile.json5"
NODE="${NODE:-$HOME/.nvm/versions/node/v22.19.0/bin/node}"
HV="${HV:-$HOME/.harmony/command-line-tools-mac26/hvigor/bin/hvigorw.js}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$HOME/.harmony/command-line-tools-mac26/sdk}"

cmd="${1:-show}"
case "$cmd" in
  show)
    echo "打包配置 (build-profile.json5 products):"
    echo "  default → 装机 (DevEco 自动签名, 可 hdc 侧载)"
    echo "  release → 上架 (发布证书, 走平台分发)"
    echo
    echo "DevEco 里切换: File > Project Structure > Signing Configs 或构建配置中选 product"
    echo "CLI 构建:      $0 build [product=default|release] [debug|release] [--install]"
    ;;
  build)
    product="${2:-default}"
    mode="${3:-debug}"
    shift 3 || true
    echo "==> 构建 product=$product buildMode=$mode"
    "$NODE" "$HV" --mode module -p module=entry@default -p product="$product" -p buildMode="$mode" assembleHap --no-daemon
    HAP="$(ls -t "$ROOT"/entry/build/default/outputs/default/*.hap 2>/dev/null | head -1)"
    echo "==> HAP: $HAP"
    if [ "$product" = "default" ] && [ "${1:-}" = "--install" ]; then
      HDC="$(command -v hdc || echo "$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc")"
      echo "==> 安装到手机"
      "$HDC" install -r "$HAP"
      "$HDC" shell aa start -a EntryAbility -b com.dsh.lite
    fi
    ;;
  *)
    echo "用法: $0 show|build [default|release] [debug|release] [--install]" >&2
    exit 2
    ;;
esac
