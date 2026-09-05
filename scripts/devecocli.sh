#!/usr/bin/env bash
# devecocli.sh —— 项目内统一调用 DevEco CLI（devecocli）的包装。
# 自动把工具链定向到本机已安装的 Command Line Tools 26.0.0.821 与 DevEco Studio，
# 无需手动 export，即可让 devecocli 构建/设备/UI/文档/检查都走正确的环境。
#
# 用法:
#   ./scripts/devecocli.sh --check-env        # 查看自动探测出的工具链路径
#   ./scripts/devecocli.sh device list        # 连接设备
#   ./scripts/devecocli.sh build              # 构建（走 devecocli 的 build）
#   ./scripts/devecocli.sh run                # 构建并安装到设备
#   ./scripts/devecocli.sh ui screenshot out.png
#   ./scripts/devecocli.sh ui layout
#   ./scripts/devecocli.sh log --level E
#   ./scripts/devecocli.sh docs search List
#   ./scripts/devecocli.sh check lint --limit 20
#   ./scripts/devecocli.sh signature generate
#   ./scripts/devecocli.sh --mcp              # 配置 deveco-mcp 到项目（注入 Agent）
#
# 可用环境变量覆盖（优先级高）：DEVECO_CLI_STUDIO_PATH / DEVECO_CLI_CLT_PATH / DEVECO_CLI_DATA_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# —— 默认工具链：Command Line Tools 26.0.0.821（Release，本工程打包用） ——
DEFAULT_CLT="$HOME/.harmony/command-line-tools-mac26"
STUDIO="/Applications/DevEco-Studio.app"

if [ "${DEVECO_CLI_CLT_PATH:-}" = "" ] && [ -d "$DEFAULT_CLT" ]; then
  export DEVECO_CLI_CLT_PATH="$DEFAULT_CLT"
fi

if [ "${DEVECO_CLI_STUDIO_PATH:-}" = "" ] && [ -d "$STUDIO" ]; then
  export DEVECO_CLI_STUDIO_PATH="$STUDIO"
fi

# —— 文档数据目录：默认给一个有写权限的位置；需要固定可 export DEVECO_CLI_DATA_DIR ——
if [ "${DEVECO_CLI_DATA_DIR:-}" = "" ]; then
  export DEVECO_CLI_DATA_DIR="$HOME/Library/Caches/deveco-cli/docs"
fi

# —— devecocli 二进制：优先用全局安装，找不到则给出提示 ——
DEVECOCLI_BIN="${DEVECOCLI_BIN:-$(command -v devecocli || true)}"
if [ -z "$DEVECOCLI_BIN" ]; then
  echo "未找到 devecocli。请先安装： npm install -g @deveco/deveco-cli@stable" >&2
  exit 1
fi

# —— 校验环境 ——
if [ "${1:-}" = "--check-env" ]; then
  echo "DevEco CLI   : $DEVECOCLI_BIN"
  echo "CLT (821)    : ${DEVECO_CLI_CLT_PATH:-<未设置>}"
  echo "DevEco Studio: ${DEVECO_CLI_STUDIO_PATH:-<未设置>}"
  echo "Data dir     : ${DEVECO_CLI_DATA_DIR:-<默认>}"
  echo "Project root : $ROOT"
  exit 0
fi

# —— 便捷入口：--mcp / --skill 把 MCP/技能配置到项目 ——
if [ "${1:-}" = "--mcp" ]; then
  shift
  exec "$DEVECOCLI_BIN" init --mcp --project "$ROOT" "$@"
fi
if [ "${1:-}" = "--skill" ]; then
  shift
  exec "$DEVECOCLI_BIN" init --skill --project "$ROOT" "$@"
fi

# —— 其余子命令直接透传（默认在项目根目录执行） ——
exec "$DEVECOCLI_BIN" "$@"
