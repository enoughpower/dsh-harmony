#!/bin/bash
# DSH push-notify 守护启动器（launchd 调用）
cd /Users/dale/Desktop/workspace/dsh-harmony/tools/push-notify
set -a
. ./.env
set +a
exec /Users/dale/.nvm/versions/node/v22.19.0/bin/node push-notify.js
