#!/bin/bash
# run-push-notify.sh —— 启动 push-notify(自定位仓库路径,不依赖绝对路径)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/tools/push-notify"
NODE="${NODE:-$(command -v node || echo "$HOME/.nvm/versions/node/v22.19.0/bin/node")}"
exec "$NODE" push-notify.js
