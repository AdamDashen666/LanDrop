#!/usr/bin/env bash
# 在 Windows 上(Git Bash)用：推送当前分支 → 等待 GitHub Actions 构建结束 → 下载产物到 out/<run_id>/
# 用法: bash scripts/ci-run.sh            （推送并跟踪本次提交触发的构建）
#       bash scripts/ci-run.sh --no-push  （不推送，手动触发一次 workflow_dispatch 并跟踪）
set -uo pipefail

GH="${GH:-gh}"
command -v "$GH" >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
cd "$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"

if [ "${1:-}" = "--no-push" ]; then
  "$GH" workflow run build.yml --ref "$BRANCH"
  sleep 5
  RUN_ID="$("$GH" run list --workflow build.yml --branch "$BRANCH" --event workflow_dispatch --limit 1 --json databaseId -q '.[0].databaseId')"
else
  git push -u origin "$BRANCH" || exit 1
  SHA="$(git rev-parse HEAD)"
  RUN_ID=""
  for _ in $(seq 1 30); do
    RUN_ID="$("$GH" run list --workflow build.yml --commit "$SHA" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)"
    [ -n "$RUN_ID" ] && break
    sleep 4
  done
fi
[ -n "$RUN_ID" ] || { echo "找不到对应的构建任务"; exit 1; }

echo "构建任务: $("$GH" run view "$RUN_ID" --json url -q .url)"
# 轮询而不是 gh run watch：网络偶尔断开时 watch 会提前退出
while :; do
  STATE="$("$GH" run view "$RUN_ID" --json status,conclusion -q '.status + " " + .conclusion' 2>/dev/null)"
  case "$STATE" in completed*) break ;; esac
  sleep 30
done
[ "$STATE" = "completed success" ]
STATUS=$?

DEST="out/$RUN_ID"
mkdir -p "$DEST"
"$GH" run download "$RUN_ID" --dir "$DEST" || true
"$GH" run view "$RUN_ID"
if [ $STATUS -ne 0 ]; then
  echo "==================== 失败步骤日志 ===================="
  "$GH" run view "$RUN_ID" --log-failed | grep -E "error:|error |\*\* .* FAILED|Assertion|XCTAssert|fatal|::error" | head -80
fi
echo "产物目录: $DEST"
find "$DEST" -type f | sed 's/^/  /'
exit $STATUS
