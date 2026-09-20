#!/usr/bin/env bash
# build-store.sh —— 产出华为应用市场（AppGallery）上架包 .app
#
# 上架版相对全功能版（master 默认）的裁剪：
#   1. Push Kit / 通知：FeatureFlags.PUSH_ENABLED=false（不建/不报 token、不申请通知权限、隐藏推送状态行）
#   2. AGC 配置：构建期间临时移出 entry/src/main/resources/rawfile/agconnect-services.json，不入包
#   3. 权限仅保留上架必需项：INTERNET / GET_NETWORK_INFO / CAMERA(user_grant)
#      （受限权限 READ_WRITE_DOWNLOAD_DIRECTORY 已从 module.json5 永久移除；导出走系统文件选择器，无需 ACL）
#   4. 用发布证书（product=release）签名，产物为 AppGallery 上架格式 .app
#
# 用法:
#   ./scripts/build-store.sh --check               # 只做上架体检，不构建
#   ./scripts/build-store.sh <versionCode> [name]  # 构建并输出 release/<name>.app
# 可选环境变量:
#   ALLOW_DIRTY=1   允许 entry/src/main、AppScope 有未提交改动
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/dev-tools.sh
source "$ROOT/scripts/dev-tools.sh"
cd "$ROOT"

CHECK_ONLY=0
INSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --install) INSTALL=1 ;;
    *) break ;;
  esac
  shift
done
VC="${1:-}"
NAME="${2:-}"

fail() { echo "✗ $*" >&2; exit 1; }
info() { echo "  • $*"; }

echo "==> 上架体检"
[ -n "${HVIGORW:-}" ] || fail "未找到 hvigorw（安装 DevEco Studio 或设置 HVIGORW）"
[ -n "${DEVECO_SDK_HOME:-}" ] || fail "未找到 SDK（设置 DEVECO_SDK_HOME）"
info "hvigorw: $HVIGORW"
info "SDK    : $DEVECO_SDK_HOME"

# --- 权限白名单 ---
PERMS="$(python3 - "$ROOT/entry/src/main/module.json5" <<'PY'
import json, re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = re.sub(r'//.*', '', s)
d = json.loads(s)
print('\n'.join(p.get('name', '') for p in d['module'].get('requestPermissions', [])))
PY
)"
echo "  权限声明:"
echo "$PERMS" | sed 's/^/    - /'
for p in $PERMS; do
  case "$p" in
    ohos.permission.INTERNET|ohos.permission.GET_NETWORK_INFO|ohos.permission.CAMERA) ;;
    *) fail "上架包不允许的权限: $p" ;;
  esac
done

FF="entry/src/main/ets/common/config/FeatureFlags.ets"
APPJSON="AppScope/app.json5"
AGC="entry/src/main/resources/rawfile/agconnect-services.json"

if grep -q 'PUSH_ENABLED: boolean = true' "$FF"; then
  info "PUSH_ENABLED=true（构建时会临时改为 false）"
else
  info "PUSH_ENABLED 已为 false"
fi
if grep -q 'BALANCE_ENABLED: boolean = true' "$FF"; then
  info "BALANCE_ENABLED=true（上架版将临时关闭余额卡与 :3082 余额请求）"
else
  info "BALANCE_ENABLED 已为 false"
fi
[ -f "$AGC" ] && info "发现 AGC 配置，构建时将移出（不入上架包）" || info "无 AGC 配置（上架版无需）"
grep -q '"name": "release"' build-profile.json5 || fail "build-profile.json5 缺少 release 签名配置"
info "release 签名配置存在"

if [ "${ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain -- entry/src/main AppScope 2>/dev/null)" ]; then
  fail "entry/src/main 或 AppScope 有未提交改动，请先提交（或 ALLOW_DIRTY=1 强制）"
fi

if [ "$CHECK_ONLY" = "1" ]; then
  echo "==> 体检通过（未构建）"
  exit 0
fi

if [ "$INSTALL" != "1" ] && [ -z "$VC" ]; then
  fail "用法: build-store.sh <versionCode> [name] | build-store.sh --check | build-store.sh --install [versionCode]"
fi
if [ -n "$VC" ]; then
  case "$VC" in (*[!0-9]*) fail "versionCode 必须为数字: $VC";; esac
fi
[ -n "$NAME" ] || NAME="DSH-Harmony-store-${VC:-$(date +%Y%m%d)}-$(date +%Y%m%d)"

# --- 临时裁剪 + 还原 ---
AGC_BAK=""
restore() {
  git checkout -- "$FF" "$APPJSON" 2>/dev/null || true
  if [ -n "$AGC_BAK" ] && [ -f "$AGC_BAK" ]; then mv "$AGC_BAK" "$AGC"; fi
}
trap restore EXIT

echo "==> 临时裁剪"
sed -i '' \
  -e 's/static readonly PUSH_ENABLED: boolean = true;/static readonly PUSH_ENABLED: boolean = false;/' \
  -e 's/static readonly BALANCE_ENABLED: boolean = true;/static readonly BALANCE_ENABLED: boolean = false;/' "$FF"
if [ -n "$VC" ]; then
  python3 - "$APPJSON" "$VC" <<'PY'
import re, sys
p, vc = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(re.sub(r'"versionCode":\s*\d+', '"versionCode": ' + vc, s))
PY
fi
if [ -f "$AGC" ]; then AGC_BAK="$(mktemp -t agconnect)"; mv "$AGC" "$AGC_BAK"; fi
info "PUSH_ENABLED=false, BALANCE_ENABLED=false, versionCode=${VC:-unchanged}"

if [ "$INSTALL" = "1" ]; then
  # 商店版功能配置 + 调试签名：可 hdc 侧载，用于真机验收商店版行为
  echo "==> 构建可侧载商店版 HAP（product=default, buildMode=release）"
  "$HVIGORW" --mode module -p module=entry@default -p product=default -p buildMode=release assembleHap --no-daemon
  HAP="$(find "$ROOT/entry/build" -name 'entry-default-signed.hap' -path '*outputs*' 2>/dev/null | head -1 || true)"
  [ -n "$HAP" ] || fail "未找到 signed HAP"
  echo "==> 安装到设备"
  [ -n "${HDC:-}" ] || fail "未找到 hdc"
  INSTALL_OUT="$("$HDC" install -r "$HAP" 2>&1 || true)"
  echo "$INSTALL_OUT" | tail -3
  case "$INSTALL_OUT" in
    *"install bundle successfully"*) ;;
    *) fail "HAP 安装失败（检查设备连接：hdc list targets / tconn）" ;;
  esac
  "$HDC" shell aa start -a EntryAbility -b com.dsh.lite >/dev/null 2>&1 || true
  echo "==> 已安装商店版行为包（PUSH_ENABLED=false, BALANCE_ENABLED=false）"
  exit 0
fi

echo "==> 构建 .app（product=release, buildMode=release）"
"$HVIGORW" --mode project -p product=release -p buildMode=release assembleApp --no-daemon

APP="$(ls -t "$ROOT"/build/outputs/release/*.app 2>/dev/null | head -1 || true)"
[ -n "$APP" ] || APP="$(find "$ROOT/build" -name '*.app' -path '*release*' 2>/dev/null | head -1 || true)"
[ -n "$APP" ] || fail "未找到 .app 产物"

mkdir -p release
cp "$APP" "release/${NAME}.app"
echo "==> 上架包: release/${NAME}.app"
echo "    size   : $(stat -f%z "release/${NAME}.app" 2>/dev/null || stat -c%s "release/${NAME}.app") bytes"
echo "    sha256 : $(shasum -a 256 "release/${NAME}.app" | awk '{print $1}')"

SIGN_TOOL="$DEVECO_SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar"
if [ -f "$SIGN_TOOL" ] && command -v java >/dev/null 2>&1; then
  echo "==> 校验签名"
  if java -jar "$SIGN_TOOL" verify-app -inFile "release/${NAME}.app" -outCertChain /tmp/dsh-store.cer -outProfile /tmp/dsh-store.p7b >/dev/null 2>&1; then
    echo "    ✓ 签名校验通过"
  else
    echo "    ! 签名校验未通过（请检查发布证书/密码）"
  fi
fi

echo "==> 完成，可上传 AppGallery: release/${NAME}.app"