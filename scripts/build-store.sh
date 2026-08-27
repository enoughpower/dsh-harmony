#!/usr/bin/env bash
# build-store.sh —— 单分支(全功能 master)产出上架裁剪包(无推送)
# 原理: 临时把 FeatureFlags.PUSH_ENABLED 置为 false + 设置 versionCode → assembleApp → 还原
# 用法: ./scripts/build-store.sh <versionCode> [产物名]
set -eo pipefail
: "${HOME:=$(cd ~ && pwd)}"
VC="${1:?用法: build-store.sh <versionCode> [产物名]}"
NAME="${2:-DSH-Harmony-store-${VC}-$(date +%Y%m%d)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE="${NODE:-$HOME/.nvm/versions/node/v22.19.0/bin/node}"
HV="${HV:-$HOME/.harmony/command-line-tools/hvigor/bin/hvigorw.js}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$HOME/.harmony/command-line-tools/sdk}"
cd "$ROOT"
[ -z "$(git status --porcelain -- entry/src/main AppScope)" ] || { echo "工作区有未提交改动,先提交"; exit 1; }
trap "git checkout -- entry/src/main AppScope 2>/dev/null || true" EXIT
echo "==> 关闭推送开关 (FeatureFlags.PUSH_ENABLED=false)"
sed -i '' 's/static readonly PUSH_ENABLED: boolean = true;/static readonly PUSH_ENABLED: boolean = false;/' entry/src/main/ets/common/config/FeatureFlags.ets
python3 - <<PY
import re, io
p = 'AppScope/app.json5'
s = open(p).read()
s = re.sub(r'"versionCode": \\d+', '"versionCode": ' + '$VC', s)
open(p, 'w').write(s)
PY
echo "==> 构建 .app(versionCode=$VC)"
"$NODE" "$HV" --mode project -p product=release -p buildMode=release assembleApp --no-daemon
APP="$(ls -t build/outputs/release/*signed.app | head -1)"
mkdir -p release
cp "$APP" "release/${NAME}.app"
echo "==> 上架包: release/${NAME}.app  ($(stat -f%z "release/${NAME}.app") bytes)"
