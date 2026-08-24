#!/bin/bash
# 同步推送服务到 ~/.dsh 运行副本（Desktop/TCC 限制：launchd 只能跑非 Desktop 路径）
set -e
SRC=/Users/dale/Desktop/workspace/dsh-harmony/tools/push-notify
DST=$HOME/.dsh/push-notify
cp "$SRC/push-notify.js" "$DST/"
[ -f "$SRC/.env" ] && cp "$SRC/.env" "$DST/"
[ -f "$DST/tokens.json" ] && cp "$DST/tokens.json" "$DST/tokens.json.bak"
echo "部署完成: 重启服务(launchctl kickstart -k gui/$(id -u)/com.dsh.push-notify)"
