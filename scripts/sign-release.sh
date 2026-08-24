#!/bin/bash
# DSH Harmony Release 签名打包脚本
# 用法: scripts/sign-release.sh [证书目录] [输出目录]
# 说明: hvigor 的 HarmonyOS 签名需要 DevEco material（CLI 无法生成），
#       Release 包改用 hap-sign-tool 手动签名（发布证书 + 发布 Profile）。
# 材料: certs/目录下 dsh-release.p12 / release.cer / release-profile.p7b
#       私钥密码来自 certs/.release-pass（或环境变量 RELEASE_PASS）
set -euo pipefail

HARMONY_ROOT="${HARMONY_ROOT:-$HOME/.harmony/command-line-tools-mac26}"
NODE="${NODE:-$HOME/.nvm/versions/node/v22.19.0/bin/node}"
HV="${HV:-$HARMONY_ROOT/hvigor/bin/hvigorw.js}"
SDK_HOME="${DEVECO_SDK_HOME:-$HARMONY_ROOT/sdk}"
SIGN_TOOL="$SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar"

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CERTS_DIR="${1:-$PROJ_DIR/certs}"
OUT_DIR="$(cd "${2:-$PROJ_DIR/entry/build/default/outputs/default}" && pwd)"

PASS="${RELEASE_PASS:-}"
if [ -z "$PASS" ] && [ -f "$CERTS_DIR/.release-pass" ]; then
  PASS="$(cat "$CERTS_DIR/.release-pass")"
fi
if [ -z "$PASS" ]; then
  echo "::error::缺少私钥密码（RELEASE_PASS 或 $CERTS_DIR/.release-pass）" >&2
  exit 1
fi

echo "== 1/3 Release 构建（unsigned） =="
export DEVECO_SDK_HOME="$SDK_HOME"
"$NODE" "$HV" --mode module -p module=entry@default -p buildMode=release assembleHap --no-daemon   || echo "  (SignHap 阶段失败为预期——改用 sign-app 手动签名)"

UNSIGNED="$OUT_DIR/entry-default-unsigned.hap"
if [ ! -f "$UNSIGNED" ]; then
  echo "::error::unsigned hap 未生成: $UNSIGNED" >&2
  exit 1
fi

echo "== 2/3 签名（发布证书） =="
STAMP="$(date +%Y%m%d-%H%M)"
SIGNED="$OUT_DIR/DSH-Harmony-release-$STAMP.hap"
java -jar "$SIGN_TOOL" sign-app -mode localSign \
  -keyAlias release -signAlg SHA256withECDSA \
  -appCertFile "$CERTS_DIR/release.cer" \
  -profileFile "$CERTS_DIR/release-profile.p7b" \
  -inFile "$UNSIGNED" -outFile "$SIGNED" \
  -keystoreFile "$CERTS_DIR/dsh-release.p12" \
  -keystorePwd "$PASS" -keyPwd "$PASS" -signCode 1

echo "== 3/3 完成 =="
ls -la "$SIGNED"
echo "Release 包: $SIGNED"
