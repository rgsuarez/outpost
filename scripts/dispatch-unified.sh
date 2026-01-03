#!/bin/bash
# Source environment if available
[[ -f /home/ubuntu/claude-executor/.env ]] && source /home/ubuntu/claude-executor/.env
# dispatch-unified.sh - Unified multi-agent dispatcher for Outpost v1.4.3
# WORKSPACE ISOLATION: Each agent gets its own repo copy - true parallelism
# v1.4.3: Auto-sync scripts from GitHub before dispatch

REPO_NAME="${1:-}"
TASK="${2:-}"
EXECUTOR="${3:---executor=claude}"

if [[ "$EXECUTOR" == --executor=* ]]; then
    EXECUTORS="${EXECUTOR#--executor=}"
elif [[ "$3" == "--executor" ]]; then
    EXECUTORS="${4:-claude}"
else
    EXECUTORS="claude"
fi

if [[ -z "$REPO_NAME" || -z "$TASK" ]]; then
    echo "Usage: dispatch-unified.sh <repo-name> \"<task>\" --executor=<agent(s)>"
    echo ""
    echo "Executors: claude | codex | gemini | aider | all"
    echo "Multiple:  --executor=claude,codex"
    exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "❌ FATAL: GITHUB_TOKEN environment variable not set"
    exit 1
fi

if [[ "$EXECUTORS" == "all" ]]; then
    EXECUTORS="claude,codex,gemini,aider"
fi

EXECUTOR_DIR="/home/ubuntu/claude-executor"
REPOS_DIR="$EXECUTOR_DIR/repos"
GITHUB_USER="rgsuarez"
BATCH_ID="$(date +%Y%m%d-%H%M%S)-batch-$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)"

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 OUTPOST UNIFIED DISPATCH v1.4.3"
echo "═══════════════════════════════════════════════════════════════"
echo "Batch ID:   $BATCH_ID"
echo "Repo:       $REPO_NAME"
echo "Task:       $TASK"
echo "Executors:  $EXECUTORS"
echo "Isolation:  ENABLED (each agent gets own workspace)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════
# v1.4.3: AUTO-SYNC DISPATCH SCRIPTS FROM GITHUB
# ═══════════════════════════════════════════════════════════════════
SCRIPTS_CACHE="$EXECUTOR_DIR/.scripts-sync"
SYNC_INTERVAL=300  # 5 minutes

sync_scripts() {
    echo "🔄 Syncing dispatch scripts from GitHub..."
    local SCRIPTS_URL="https://raw.githubusercontent.com/rgsuarez/outpost/main/scripts"
    
    for script in dispatch.sh dispatch-codex.sh dispatch-gemini.sh dispatch-aider.sh; do
        curl -sL "$SCRIPTS_URL/$script" -o "$EXECUTOR_DIR/$script.new" 2>/dev/null
        if [[ -s "$EXECUTOR_DIR/$script.new" ]]; then
            mv "$EXECUTOR_DIR/$script.new" "$EXECUTOR_DIR/$script"
            chmod +x "$EXECUTOR_DIR/$script"
        else
            rm -f "$EXECUTOR_DIR/$script.new"
        fi
    done
    
    # Also sync this unified script
    curl -sL "$SCRIPTS_URL/dispatch-unified.sh" -o "$EXECUTOR_DIR/dispatch-unified.sh.new" 2>/dev/null
    if [[ -s "$EXECUTOR_DIR/dispatch-unified.sh.new" ]]; then
        mv "$EXECUTOR_DIR/dispatch-unified.sh.new" "$EXECUTOR_DIR/dispatch-unified.sh"
        chmod +x "$EXECUTOR_DIR/dispatch-unified.sh"
    else
        rm -f "$EXECUTOR_DIR/dispatch-unified.sh.new"
    fi
    
    date +%s > "$SCRIPTS_CACHE"
    echo "   Scripts synced from GitHub"
}

# Check if sync needed (every 5 minutes)
if [[ -f "$SCRIPTS_CACHE" ]]; then
    LAST_SYNC=$(cat "$SCRIPTS_CACHE")
    NOW=$(date +%s)
    if (( NOW - LAST_SYNC > SYNC_INTERVAL )); then
        sync_scripts
    else
        echo "📦 Scripts current (synced $(( (NOW - LAST_SYNC) / 60 ))m ago)"
    fi
else
    sync_scripts
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# PRE-FLIGHT: UPDATE SHARED REPO CACHE
# ═══════════════════════════════════════════════════════════════════
SOURCE_REPO="$REPOS_DIR/$REPO_NAME"
LOCKFILE="$EXECUTOR_DIR/.cache-lock-$REPO_NAME"

echo "📦 Pre-flight: Updating shared cache..."
(
    flock -w 30 200 || { echo "⚠️ Could not acquire cache lock, proceeding anyway"; }
    
    if [[ ! -d "$SOURCE_REPO" ]]; then
        echo "   Initial clone..."
        mkdir -p "$REPOS_DIR"
        git clone "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git" "$SOURCE_REPO" 2>&1
    fi
    
    cd "$SOURCE_REPO"
    echo "   Fetching latest..."
    git fetch origin 2>&1
    
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [[ -z "$DEFAULT_BRANCH" ]]; then
        DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
    fi
    DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
    
    git reset --hard "origin/$DEFAULT_BRANCH" 2>&1
    CACHE_SHA=$(git rev-parse HEAD)
    echo "   Cache ready: $CACHE_SHA"
    
) 200>"$LOCKFILE"

export OUTPOST_CACHE_READY=1
export GITHUB_TOKEN

# ═══════════════════════════════════════════════════════════════════
# DISPATCH TO AGENTS
# ═══════════════════════════════════════════════════════════════════
IFS=',' read -ra EXEC_ARRAY <<< "$EXECUTORS"
EXEC_COUNT=${#EXEC_ARRAY[@]}

if [[ $EXEC_COUNT -gt 1 ]]; then
    echo ""
    echo "🔀 Parallel execution ($EXEC_COUNT agents, isolated workspaces)"
fi

PIDS=()
for executor in "${EXEC_ARRAY[@]}"; do
    executor=$(echo "$executor" | xargs)
    echo ""
    echo "📤 Dispatching to $executor..."
    
    case "$executor" in
        claude)
            "$EXECUTOR_DIR/dispatch.sh" "$REPO_NAME" "$TASK" &
            PIDS+=($!)
            ;;
        codex)
            "$EXECUTOR_DIR/dispatch-codex.sh" "$REPO_NAME" "$TASK" &
            PIDS+=($!)
            ;;
        gemini)
            "$EXECUTOR_DIR/dispatch-gemini.sh" "$REPO_NAME" "$TASK" &
            PIDS+=($!)
            ;;
        aider)
            "$EXECUTOR_DIR/dispatch-aider.sh" "$REPO_NAME" "$TASK" &
            PIDS+=($!)
            ;;
        *)
            echo "⚠️ Unknown executor: $executor"
            ;;
    esac
done

if [[ ${#PIDS[@]} -gt 0 ]]; then
    echo ""
    echo "⏳ Waiting for all agents..."
    for pid in "${PIDS[@]}"; do
        wait $pid
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ UNIFIED DISPATCH COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo "Batch: $BATCH_ID"
echo "Use 'list-runs.sh' to see results"
echo "Use 'promote-workspace.sh <run-id>' to push changes"
