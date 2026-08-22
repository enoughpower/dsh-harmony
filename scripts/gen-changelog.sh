#!/usr/bin/env bash
# gen-changelog.sh —— 从 git log 生成按天分组的 changelog 片段（追加到 CHANGELOG.md 顶部）。
# 约定：提交信息使用 Conventional Commits 前缀（feat/fix/perf/docs/test/chore/refactor）。
# 用法:
#   ./scripts/gen-changelog.sh                # 今天的变更
#   ./scripts/gen-changelog.sh 2026-08-23     # 指定日期
#   ./scripts/gen-changelog.sh --dry-run      # 只打印不写文件
#   ./scripts/gen-changelog.sh --commit       # 生成并自动 git commit 到 CHANGELOG.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DATE="${1:-$(date +%F)}"
DO_COMMIT=0
DRY_RUN=0
case "$1" in
  --commit) DATE=$(date +%F); DO_COMMIT=1 ;;
  --dry-run) DATE=$(date +%F); DRY_RUN=1 ;;
  ""|--*) ;;
esac

SINCE="$DATE 00:00:00"
UNTIL="$DATE 23:59:59"
LOG=$(git log --since="$SINCE" --until="$UNTIL" --no-merges --pretty=format:"%s" 2>/dev/null || true)

if [ -z "$LOG" ]; then
  echo "该日期没有提交记录: $DATE"
  exit 0
fi

CHANGELOG="$ROOT/CHANGELOG.md"
[ -f "$CHANGELOG" ] || { echo "# Changelog" > "$CHANGELOG"; echo >> "$CHANGELOG"; }

group() {
  local label="$1"; shift
  local entries=$(echo "$LOG" | grep -iE "^$label" || true)
  [ -n "$entries" ] && {
    echo "### $label"
    echo "$entries" | sed -E 's/^[a-z]+(\([^)]*\))?:? ?/- /I'
    echo
  }
}

if [ "$DRY_RUN" = "1" ]; then
  echo "## $DATE"
  echo
  group "feat"
  group "fix"
  group "perf"
  group "refactor"
  group "docs"
  group "test"
  group "chore"
  echo "（dry-run 结束，未写入）"
  exit 0
fi

TMP="$(mktemp)"
{
  echo "## $DATE"
  echo
  group "feat"
  group "fix"
  group "perf"
  group "refactor"
  group "docs"
  group "test"
  group "chore"
  echo "---"
  echo
  cat "$CHANGELOG"
} > "$TMP"
mv "$TMP" "$CHANGELOG"

echo "已更新 $CHANGELOG（$DATE）"
if [ "$DO_COMMIT" = "1" ]; then
  git add "$CHANGELOG"
  git commit -m "docs: changelog $DATE" --no-verify
fi
