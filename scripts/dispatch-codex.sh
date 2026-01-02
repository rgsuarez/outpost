#!/bin/bash
# dispatch-codex.sh - Outpost Codex dispatcher
#
# Usage: ./dispatch-codex.sh <repo> <task description>

set -e

REPO=$1
shift
TASK="$*"
RUN_ID=$(date +%Y%m%d-%H%M%S)-codex-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
RUN_DIR="/home/ubuntu/claude-executor/runs/$RUN_ID"
REPO_DIR="/home/ubuntu/claude-executor/repos/$REPO"

mkdir -p "$RUN_DIR"
echo "$TASK" > "$RUN_DIR/task.md"
echo "{\"run_id\": \"$RUN_ID\", \"repo\": \"$REPO\", \"executor\": \"codex\", \"started\": \"$(date -Iseconds)\", \"status\": \"running\"}" > "$RUN_DIR/summary.json"

if [ ! -d "$REPO_DIR" ]; then
    git clone "https://github.com/rgsuarez/$REPO.git" "$REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
git reset --hard origin/main
git clean -fd

BEFORE_SHA=$(git rev-parse HEAD)

echo "Starting OpenAI Codex at $(date -Iseconds)" >> "$RUN_DIR/output.log"

codex exec \
    --full-auto \
    --sandbox workspace-write \
    "$TASK" 2>&1 | tee -a "$RUN_DIR/output.log"

CODEX_EXIT=$?

AFTER_SHA=$(git rev-parse HEAD 2>/dev/null || echo "$BEFORE_SHA")

if [ "$BEFORE_SHA" != "$AFTER_SHA" ]; then
    git diff "$BEFORE_SHA" "$AFTER_SHA" > "$RUN_DIR/diff.patch"
    CHANGES="committed"
elif [ -n "$(git status --porcelain)" ]; then
    git diff > "$RUN_DIR/diff.patch"
    CHANGES="uncommitted"
else
    CHANGES="none"
fi

STATUS=$([ $CODEX_EXIT -eq 0 ] && echo "success" || echo "failed")
echo "{\"run_id\": \"$RUN_ID\", \"repo\": \"$REPO\", \"executor\": \"codex\", \"completed\": \"$(date -Iseconds)\", \"status\": \"$STATUS\", \"exit_code\": $CODEX_EXIT, \"before_sha\": \"$BEFORE_SHA\", \"after_sha\": \"$AFTER_SHA\", \"changes\": \"$CHANGES\"}" > "$RUN_DIR/summary.json"

echo "=== RUN COMPLETE (CODEX) ==="
echo "Run ID: $RUN_ID"
cat "$RUN_DIR/summary.json"
