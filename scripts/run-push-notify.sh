#!/bin/bash
# run-push-notify.sh —— 启动 push-notify(自定位,不依赖绝对路径)
HERE="$(cd "$(dirname "$0")" && pwd)"
# 部署副本(与 push-notify.js 同目录)或仓库开发布局(../tools/push-notify)均兼容
if [ -f "$HERE/push-notify.js" ]; then cd "$HERE"; else cd "$HERE/../tools/push-notify"; fi
NODE="${NODE:-$(command -v node || echo "$HOME/.nvm/versions/node/v22.19.0/bin/node")}"
exec "$NODE" --env-file=.env push-notify.js
