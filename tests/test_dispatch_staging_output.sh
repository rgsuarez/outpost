#!/usr/bin/env bash
set -euo pipefail

SCRIPT="/home/richie/projects/outpost/scripts/dispatch-unified.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for staging output test" >&2
  exit 1
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

RUN_ID="run-123"
RUN_DIR="$ROOT/runs/$RUN_ID"
WORKSPACE="$ROOT/workspace"

mkdir -p "$RUN_DIR" "$WORKSPACE"

cat > "$RUN_DIR/summary.json" <<SUMMARY
{
  "run_id": "$RUN_ID",
  "repo": "outpost",
  "executor": "claude",
  "model": "claude-opus-4-5-20251101",
  "started": "2026-01-08T07:00:00Z",
  "completed": "2026-01-08T07:00:10Z",
  "status": "success",
  "exit_code": 0,
  "workspace": "$WORKSPACE"
}
SUMMARY

echo "diff --git a/foo.txt b/foo.txt" > "$RUN_DIR/diff.patch"
echo "task body" > "$RUN_DIR/task.md"

OUTPOST_TEST_MODE=1 \
OUTPOST_TEST_STAGE_ONLY=1 \
OUTPOST_TEST_RUN_DIR="$ROOT" \
OUTPOST_TEST_EXECUTOR="claude" \
OUTPOST_TEST_RUN_ID="$RUN_ID" \
OUTPOST_TEST_TASK_SUMMARY="test staging" \
GITHUB_TOKEN="dummy" \
  bash "$SCRIPT" outpost "test task" --staging >/dev/null

ENTRY_DIR="$WORKSPACE/.staging/inbox/$RUN_ID"

[[ -f "$ENTRY_DIR/manifest.json" ]]
[[ -f "$ENTRY_DIR/status.json" ]]
[[ -d "$ENTRY_DIR/outputs/entries" ]]
[[ -f "$ENTRY_DIR/outputs/artifacts/summary.json" ]]
[[ -f "$ENTRY_DIR/outputs/artifacts/diff.patch" ]]
[[ -f "$ENTRY_DIR/outputs/artifacts/task.md" ]]

jq -e '.command_id == "'$RUN_ID'" and .worker_id == "claude"' "$ENTRY_DIR/manifest.json" >/dev/null
jq -e '.status == "complete" and .exit_code == 0' "$ENTRY_DIR/status.json" >/dev/null

echo "staging output test passed"
