#!/bin/bash
# dispatch-gemini.sh - Headless Gemini CLI executor for Outpost
# Uses Google AI Ultra subscription via OAuth
# Part of the Outpost multi-agent executor system

set -e

REPO_NAME="${1:-}"
TASK="${2:-}"

if [[ -z "$REPO_NAME" || -z "$TASK" ]]; then
    echo "Usage: dispatch-gemini.sh <repo-name> \"<task>\""
    echo "Example: dispatch-gemini.sh swords-of-chaos-reborn \"Fix the bug in server.js\""
    exit 1
fi

# Configuration
EXECUTOR_DIR="/home/ubuntu/claude-executor"
REPOS_DIR="$EXECUTOR_DIR/repos"
RUNS_DIR="$EXECUTOR_DIR/runs"
GITHUB_USER="rgsuarez"
# Note: Token should be set via environment variable in production
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Generate run ID with gemini identifier
RUN_ID="$(date +%Y%m%d-%H%M%S)-gemini-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
RUN_DIR="$RUNS_DIR/$RUN_ID"

echo "🚀 Gemini dispatch starting..."
echo "Run ID: $RUN_ID"
echo "Repo: $REPO_NAME"
echo "Task: $TASK"

# Create run directory
mkdir -p "$RUN_DIR"

# Save task
echo "$TASK" > "$RUN_DIR/task.md"

# Clone or update repo
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

# Get current SHA
BEFORE_SHA=$(git rev-parse HEAD)
echo "Before SHA: $BEFORE_SHA"

# Execute Gemini CLI in headless mode with YOLO (auto-approve all tools)
echo "🤖 Running Gemini CLI..."
export HOME=/home/ubuntu
gemini -p "$TASK" --yolo 2>&1 | tee "$RUN_DIR/output.log"
EXIT_CODE=${PIPESTATUS[0]}

# Get after SHA and diff
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

# Determine status
if [[ $EXIT_CODE -eq 0 ]]; then
    STATUS="success"
else
    STATUS="failed"
fi

# Create summary
cat > "$RUN_DIR/summary.json" << SUMMARY
{
  "run_id": "$RUN_ID",
  "repo": "$REPO_NAME",
  "executor": "gemini",
  "model": "gemini-2.5-pro",
  "completed": "$(date -Iseconds)",
  "status": "$STATUS",
  "exit_code": $EXIT_CODE,
  "before_sha": "$BEFORE_SHA",
  "after_sha": "$AFTER_SHA",
  "changes": "$CHANGES"
}
SUMMARY

echo ""
echo "✅ Gemini dispatch complete"
echo "Run ID: $RUN_ID"
echo "Status: $STATUS"
echo "Changes: $CHANGES"
echo ""
echo "Results in: $RUN_DIR/"
