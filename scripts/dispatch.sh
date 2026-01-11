#!/bin/bash
# Source environment if available
[[ -f /home/ubuntu/claude-executor/.env ]] && source /home/ubuntu/claude-executor/.env

# AUTO-PRIVILEGE DROP: Ensure execution as ubuntu user
if [[ $EUID -eq 0 ]]; then
    echo "🔒 Auto-dropping privileges from root to ubuntu user..."
    exec sudo -u ubuntu -E HOME=/home/ubuntu bash "$0" "$@"
fi

# dispatch.sh - Headless Claude Code executor for Outpost v1.6
# WORKSPACE ISOLATION: Each run gets its own repo copy
# v1.6: Namespace stripping support (rgsuarez/repo → repo)
# v1.5: Stack Lock enforcement, --stack-override, --repo-url support
#
# Test cases for namespace stripping:
#   ./dispatch.sh "awsaudit" "task"           → awsaudit (unchanged)
#   ./dispatch.sh "rgsuarez/awsaudit" "task"  → awsaudit (namespace stripped)
#   ./dispatch.sh "org/ns/repo" "task"        → repo (all namespaces stripped)

# Argument parsing for optional flags
REPO_NAME=""
TASK=""
REPO_URL=""
STACK_OVERRIDE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo-url=*) REPO_URL="${1#*=}"; shift ;;
        --stack-override=*) STACK_OVERRIDE="${1#*=}"; shift ;;
        *) if [[ -z "$REPO_NAME" ]]; then REPO_NAME="$1"; elif [[ -z "$TASK" ]]; then TASK="$1"; fi; shift ;;
    esac
done

# Strip GitHub username prefix if present (e.g., "rgsuarez/awsaudit" → "awsaudit")
# Supports both bare names and namespaced names for external API compatibility
if [[ "$REPO_NAME" == */* ]]; then
    ORIGINAL_REPO_NAME="$REPO_NAME"
    REPO_NAME="${REPO_NAME##*/}"
    echo "📝 Stripped namespace: $ORIGINAL_REPO_NAME → $REPO_NAME"
fi

if [[ -z "$REPO_NAME" || -z "$TASK" ]]; then
    echo "Usage: dispatch.sh <repo-name> \"<task>\" [--repo-url=<url>] [--stack-override=<stack>]"
    exit 1
fi

# C2 FIX: Require GITHUB_TOKEN from environment, fail fast if missing
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "❌ FATAL: GITHUB_TOKEN environment variable not set"
    echo "   Set it in /home/ubuntu/.bashrc or pass via SSM"
    exit 1
fi

EXECUTOR_DIR="/home/ubuntu/claude-executor"
REPOS_DIR="$EXECUTOR_DIR/repos"
RUNS_DIR="$EXECUTOR_DIR/runs"
GITHUB_USER="rgsuarez"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-600}"  # H1 FIX: 10 minute default timeout

RUN_ID="$(date +%Y%m%d-%H%M%S)-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
RUN_DIR="$RUNS_DIR/$RUN_ID"
WORKSPACE="$RUN_DIR/workspace"

echo "🚀 Claude Code dispatch starting..."
echo "Run ID: $RUN_ID"
echo "Model: claude-opus-4-5-20251101"
echo "Repo: $REPO_NAME"
echo "Task: $TASK"

mkdir -p "$RUN_DIR"
echo "$TASK" > "$RUN_DIR/task.md"

# H4 FIX: Write running status immediately
cat > "$RUN_DIR/summary.json" << SUMMARY
{
  "run_id": "$RUN_ID",
  "repo": "$REPO_NAME",
  "executor": "claude-code",
  "model": "claude-opus-4-5-20251101",
  "started": "$(date -Iseconds)",
  "status": "running"
}
SUMMARY

exec > >(tee -a "$RUN_DIR/output.log") 2>&1

SOURCE_REPO="$REPOS_DIR/$REPO_NAME"

# Only update cache if not already done by unified dispatcher
if [[ -z "$OUTPOST_CACHE_READY" ]]; then
    if [[ ! -d "$SOURCE_REPO" ]]; then
        echo "📦 Initial clone from GitHub..."
        mkdir -p "$REPOS_DIR"
        CLONE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
        [[ -n "$REPO_URL" ]] && CLONE_URL="$REPO_URL"
        
        if ! git clone "$CLONE_URL" "$SOURCE_REPO" 2>&1; then
            echo "❌ Git clone failed"
            cat > "$RUN_DIR/summary.json" << SUMMARY
{"run_id":"$RUN_ID","repo":"$REPO_NAME","executor":"claude-code","status":"failed","error":"git clone failed"}
SUMMARY
            exit 1
        fi
    fi
    
    echo "📦 Updating cache..."
    cd "$SOURCE_REPO"
    git fetch origin 2>&1
    
    # C3 FIX: Detect default branch instead of hardcoding main
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [[ -z "$DEFAULT_BRANCH" ]]; then
        # Fallback: try to detect from remote
        DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    fi
    DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"  # Ultimate fallback
    
    git reset --hard "origin/$DEFAULT_BRANCH" 2>&1 || echo "⚠️ Cache update failed"
else
    echo "📦 Using pre-warmed cache"
fi

echo "📂 Creating isolated workspace..."
mkdir -p "$WORKSPACE"
rsync -a --delete "$SOURCE_REPO/" "$WORKSPACE/"

cd "$WORKSPACE"

# --- STACK LOCK ENFORCEMENT (v1.5) ---
echo "🔍 Detecting stack..."
if [[ -n "$STACK_OVERRIDE" ]]; then
    DETECTED_STACK="$STACK_OVERRIDE"
    echo "Using stack override: $DETECTED_STACK"
else
    # Ensure blueprint package is available in PYTHONPATH
    # On Outpost, we expect blueprint source in /home/ubuntu/blueprint
    BLUEPRINT_LIB="/home/ubuntu/blueprint/src"
    if [[ -d "$BLUEPRINT_LIB" ]]; then
        DETECTED_STACK=$(PYTHONPATH="$BLUEPRINT_LIB" python3 -c "from blueprint.stack.detector import detect_stack; print(detect_stack('.')['primary_stack'])" 2>/dev/null || echo "unknown")
    else
        DETECTED_STACK="unknown"
    fi
    echo "Detected stack: $DETECTED_STACK"
fi

if [[ "$DETECTED_STACK" != "unknown" ]]; then
    LANGUAGE_LOCK="LANGUAGE_LOCK: This is a $DETECTED_STACK project. ALL code solutions MUST use $DETECTED_STACK. DO NOT suggest other language alternatives."
    TASK=$(printf "$LANGUAGE_LOCK\n\n$TASK")
    echo "Stack lock applied: $DETECTED_STACK"
fi
# -------------------------------------

BEFORE_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
echo "Workspace SHA: $BEFORE_SHA"

echo "🤖 Running Claude Code (Opus 4.5)..."
export HOME=/home/ubuntu

# H1 FIX: Wrap in timeout
timeout "$AGENT_TIMEOUT" claude --print --dangerously-skip-permissions "$TASK" 2>&1
EXIT_CODE=$?

# Check for timeout
if [[ $EXIT_CODE -eq 124 ]]; then
    echo "⚠️ Agent timed out after ${AGENT_TIMEOUT}s"
    STATUS="timeout"
else
    [[ $EXIT_CODE -eq 0 ]] && STATUS="success" || STATUS="failed"
fi

AFTER_SHA=$(git rev-parse HEAD 2>/dev/null || echo "$BEFORE_SHA")
if [[ "$BEFORE_SHA" != "$AFTER_SHA" && "$BEFORE_SHA" != "unknown" ]]; then
    git diff "$BEFORE_SHA" "$AFTER_SHA" > "$RUN_DIR/diff.patch" 2>/dev/null
    CHANGES="committed"
else
    git diff > "$RUN_DIR/diff.patch" 2>/dev/null
    [[ -s "$RUN_DIR/diff.patch" ]] && CHANGES="uncommitted" || CHANGES="none"
fi

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
  "changes": "$CHANGES",
  "workspace": "$WORKSPACE"
}
SUMMARY

echo ""
echo "✅ Claude Code dispatch complete"
echo "Run ID: $RUN_ID"
echo "Status: $STATUS"
echo "Changes: $CHANGES"
echo "Workspace: $WORKSPACE"
