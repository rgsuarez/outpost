#!/bin/bash
# dispatch.sh - Headless Claude Code executor for Outpost
# Uses Claude Max subscription with Opus 4.5 model

set -e

REPO_NAME="${1:-}"
TASK="${2:-}"

if [[ -z "$REPO_NAME" || -z "$TASK" ]]; then
    echo "Usage: dispatch.sh <repo-name> \"<task>\""
    exit 1
fi

EXECUTOR_DIR="/home/ubuntu/claude-executor"
REPOS_DIR="$EXECUTOR_DIR/repos"
RUNS_DIR="$EXECUTOR_DIR/runs"
GITHUB_USER="rgsuarez"
GITHUB_TOKEN="${GITHUB_TOKEN:-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}"

RUN_ID="$(date +%Y%m%d-%H%M%S)-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
RUN_DIR="$RUNS_DIR/$RUN_ID"

echo "🚀 Claude Code dispatch starting..."
echo "Run ID: $RUN_ID"
echo "Model: claude-opus-4-5-20251101"
echo "Repo: $REPO_NAME"
echo "Task: $TASK"

mkdir -p "$RUN_DIR"
echo "$TASK" > "$RUN_DIR/task.md"

mkdir -p "$REPOS_DIR"
REPO_PATH="$REPOS_DIR/$REPO_NAME"

if [[ -d "$REPO_PATH" ]]; then
    echo "📦 Updating existing repo..."
    cd "$REPO_PATH"
    git fetch origin
    git reset --hard origin/main
else
    echo "📦 Cloning repo..."
    cd "$REPOS_DIR"
    git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
fi

cd "$REPO_PATH"
BEFORE_SHA=$(git rev-parse HEAD)
echo "Before SHA: $BEFORE_SHA"

echo "🤖 Running Claude Code (Opus 4.5)..."
export HOME=/home/ubuntu
claude --model claude-opus-4-5-20251101 --dangerously-skip-permissions -p "$TASK" 2>&1 | tee "$RUN_DIR/output.log"
EXIT_CODE=${PIPESTATUS[0]}

AFTER_SHA=$(git rev-parse HEAD)
if [[ "$BEFORE_SHA" != "$AFTER_SHA" ]]; then
    git diff "$BEFORE_SHA" "$AFTER_SHA" > "$RUN_DIR/diff.patch"
    CHANGES="committed"
else
    git diff > "$RUN_DIR/diff.patch"
    if [[ -s "$RUN_DIR/diff.patch" ]]; then
        CHANGES="uncommitted"
    else
        CHANGES="none"
    fi
fi

[[ $EXIT_CODE -eq 0 ]] && STATUS="success" || STATUS="failed"

cat > "$RUN_DIR/summary.json" << SUMMARY
{
  "run_id": "$RUN_ID",
  "repo": "$REPO_NAME",
  "executor": "claude-code",
  "model": "claude-opus-4-5-20251101",
  "completed": "$(date -Iseconds)",
  "status": "$STATUS",
  "exit_code": $EXIT_CODE,
  "before_sha": "$BEFORE_SHA",
  "after_sha": "$AFTER_SHA",
  "changes": "$CHANGES"
}
SUMMARY

echo ""
echo "✅ Claude Code dispatch complete"
echo "Run ID: $RUN_ID"
echo "Status: $STATUS"
echo "Changes: $CHANGES"
