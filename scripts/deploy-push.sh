#!/usr/bin/env bash
# deploy-push.sh —— 部署 push-notify 到 ~/.dsh/push-notify 并注册 launchd 常驻(本机)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.dsh/push-notify"
mkdir -p "$DEST"
cp "$ROOT/tools/push-notify/push-notify.js" "$DEST/"
cp "$ROOT/tools/push-notify/.env.example" "$DEST/.env.example"
cp "$ROOT/scripts/run-push-notify.sh" "$DEST/run-push-notify.sh"
chmod +x "$DEST/run-push-notify.sh"
# events.mux WS 需 ws 库以携带 dsh-auth cookie；无则退回全局 WebSocket（scenario-3 降级）
if [ -x "$(command -v npm)" ]; then ( cd "$DEST" && npm install ws --no-save --no-audit --no-fund >/dev/null 2>&1 || true ); fi
PLIST="$HOME/Library/LaunchAgents/com.dsh.push-notify.plist"
sed "s|<string>~/.dsh/push-notify/run-push-notify.sh</string>|<string>"$DEST"/run-push-notify.sh</string>|" \
  "$ROOT/scripts/com.dsh.push-notify.plist" > "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "deploy done: $DEST"
