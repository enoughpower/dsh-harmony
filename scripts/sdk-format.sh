#!/bin/bash
# 切换 build-profile 的 SDK 版本格式（CLI 与 DevEco 要求相反）
#   usage: scripts/sdk-format.sh cli|deveco
set -e
P=build-profile.json5
case "$1" in
  cli)
    sed -i '' 's|"compileSdkVersion": "26.0.0(26)"|"compileSdkVersion": "26.0.0"|; s|"targetSdkVersion": "26.0.0(26)"|"targetSdkVersion": "26.0.0"|' "$P"
    echo 'build-profile -> CLI 格式'
    ;;
  deveco)
    sed -i '' 's|"compileSdkVersion": "26.0.0"|"compileSdkVersion": "26.0.0(26)"|; s|"targetSdkVersion": "26.0.0"|"targetSdkVersion": "26.0.0(26)"|' "$P"
    echo 'build-profile -> DevEco 格式'
    ;;
  *) echo 'usage: sdk-format.sh cli|deveco'; exit 1;;
esac