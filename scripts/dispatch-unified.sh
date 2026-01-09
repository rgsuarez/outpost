#!/bin/bash
# Source environment if available
[[ -f /home/ubuntu/claude-executor/.env ]] && source /home/ubuntu/claude-executor/.env

# AUTO-PRIVILEGE DROP: Ensure execution as ubuntu user
# NOTE: Don't use 'exec' here - it breaks background job context for run_with_capture
if [[ $EUID -eq 0 ]]; then
    echo "🔒 Auto-dropping privileges from root to ubuntu user..."
    sudo -u ubuntu -E HOME=/home/ubuntu bash "$0" "$@"
    exit $?
fi

# dispatch-unified.sh - Unified multi-agent dispatcher for Outpost v1.8.0
# WORKSPACE ISOLATION: Each agent gets its own repo copy - true parallelism
# v1.5.0: Context injection support (--context flag)

# ═══════════════════════════════════════════════════════════════════
# ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════
REPO_NAME="${1:-}"
TASK="${2:-}"
shift 2 2>/dev/null || true

# Defaults
EXECUTORS="claude"
CONTEXT_LEVEL="off"
STAGING_MODE=0
STAGING_ROOT=".staging"

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --executor=*)
            EXECUTORS="${1#--executor=}"
            shift
            ;;
        --executor)
            EXECUTORS="${2:-claude}"
            shift 2
            ;;
        --context=*)
            CONTEXT_LEVEL="${1#--context=}"
            shift
            ;;
        --context)
            # If next arg is a level, use it; otherwise default to standard
            if [[ "${2:-}" =~ ^(minimal|standard|full|[0-9]+)$ ]]; then
                CONTEXT_LEVEL="$2"
                shift 2
            else
                CONTEXT_LEVEL="standard"
                shift
            fi
            ;;
        --staging)
            STAGING_MODE=1
            shift
            ;;
        *)
            echo "⚠️ Unknown argument: $1"
            shift
            ;;
    esac
done

if [[ -z "$REPO_NAME" || -z "$TASK" ]]; then
    echo "Usage: dispatch-unified.sh <repo-name> \"<task>\" [--executor=<agent(s)>] [--context=<level>] [--staging]"
    echo ""
    echo "Executors: claude | codex | gemini | aider | grok | all"
    echo "Multiple:  --executor=claude,codex"
    echo ""
    echo "Context Injection (v1.5.0):"
    echo "  --context              Enable with standard level (1200 tokens)"
    echo "  --context=minimal      600 tokens (SOUL + JOURNAL)"
    echo "  --context=standard     1200 tokens (+ ANCHORS + PROFILE)"
    echo "  --context=full         1800 tokens (+ ROADMAP)"
    echo "  --context=<number>     Custom token budget (600-2000)"
    echo ""
    echo "Staging Mode:"
    echo "  --staging              Enable staging output + read-only git mode"
    exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "❌ FATAL: GITHUB_TOKEN environment variable not set"
    exit 1
fi

if [[ "$EXECUTORS" == "all" ]]; then
    EXECUTORS="claude,codex,gemini,aider,grok"
fi

EXECUTOR_DIR="/home/ubuntu/claude-executor"
REPOS_DIR="$EXECUTOR_DIR/repos"
SCRIPTS_DIR="$EXECUTOR_DIR/scripts"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_LIB_DIR="$SCRIPT_DIR/lib"
GITHUB_USER="rgsuarez"
BATCH_ID="$(date +%Y%m%d-%H%M%S)-batch-$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)"
TASK_SUMMARY="${TASK:0:200}"
TEST_STAGE_ONLY=0
if [[ "${OUTPOST_TEST_MODE:-0}" == "1" && "${OUTPOST_TEST_STAGE_ONLY:-0}" == "1" ]]; then
    TEST_STAGE_ONLY=1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 OUTPOST UNIFIED DISPATCH v1.5.0"
echo "═══════════════════════════════════════════════════════════════"
echo "Batch ID:   $BATCH_ID"
echo "Repo:       $REPO_NAME"
echo "Task:       ${TASK:0:100}$([ ${#TASK} -gt 100 ] && echo '...')"
echo "Executors:  $EXECUTORS"
echo "Context:    $CONTEXT_LEVEL"
echo "Staging:    $([[ $STAGING_MODE -eq 1 ]] && echo 'ENABLED' || echo 'OFF')"
echo "Isolation:  ENABLED (each agent gets own workspace)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════
# AUTO-SYNC DISPATCH SCRIPTS FROM GITHUB
# ═══════════════════════════════════════════════════════════════════
SCRIPTS_CACHE="$EXECUTOR_DIR/.scripts-sync"
SYNC_INTERVAL=300  # 5 minutes

sync_scripts() {
    echo "🔄 Syncing dispatch scripts from GitHub..."
    local SCRIPTS_URL="https://raw.githubusercontent.com/rgsuarez/outpost/main/scripts"
    
    # Sync main dispatch scripts
    for script in dispatch.sh dispatch-codex.sh dispatch-gemini.sh dispatch-aider.sh dispatch-grok.sh; do
        curl -sL "$SCRIPTS_URL/$script" -o "$EXECUTOR_DIR/$script.new" 2>/dev/null
        if [[ -s "$EXECUTOR_DIR/$script.new" ]]; then
            mv "$EXECUTOR_DIR/$script.new" "$EXECUTOR_DIR/$script"
            chmod +x "$EXECUTOR_DIR/$script"
        else
            rm -f "$EXECUTOR_DIR/$script.new"
        fi
    done
    
    # Sync unified dispatcher
    curl -sL "$SCRIPTS_URL/dispatch-unified.sh" -o "$EXECUTOR_DIR/dispatch-unified.sh.new" 2>/dev/null
    if [[ -s "$EXECUTOR_DIR/dispatch-unified.sh.new" ]]; then
        mv "$EXECUTOR_DIR/dispatch-unified.sh.new" "$EXECUTOR_DIR/dispatch-unified.sh"
        chmod +x "$EXECUTOR_DIR/dispatch-unified.sh"
    else
        rm -f "$EXECUTOR_DIR/dispatch-unified.sh.new"
    fi
    
    # Sync context injection scripts (v1.5.0)
    mkdir -p "$SCRIPTS_DIR"
    for script in assemble-context.sh scrub-secrets.sh grok-agent.py; do
        curl -sL "$SCRIPTS_URL/$script" -o "$SCRIPTS_DIR/$script.new" 2>/dev/null
        if [[ -s "$SCRIPTS_DIR/$script.new" ]]; then
            mv "$SCRIPTS_DIR/$script.new" "$SCRIPTS_DIR/$script"
            chmod +x "$SCRIPTS_DIR/$script"
        else
            rm -f "$SCRIPTS_DIR/$script.new"
        fi
    done

    # Sync staging support scripts
    mkdir -p "$SCRIPTS_DIR/lib"
    for script in lib/staging-utils.sh lib/git-readonly-wrapper.sh; do
        curl -sL "$SCRIPTS_URL/$script" -o "$SCRIPTS_DIR/$script.new" 2>/dev/null
        if [[ -s "$SCRIPTS_DIR/$script.new" ]]; then
            mv "$SCRIPTS_DIR/$script.new" "$SCRIPTS_DIR/$script"
            chmod +x "$SCRIPTS_DIR/$script"
        else
            rm -f "$SCRIPTS_DIR/$script.new"
        fi
    done
    
    date +%s > "$SCRIPTS_CACHE"
    echo "   Scripts synced from GitHub"
}

# Check if sync needed (every 5 minutes)
if [[ $TEST_STAGE_ONLY -eq 0 ]]; then
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
fi

# ═══════════════════════════════════════════════════════════════════
# STAGING MODE SETUP
# ═══════════════════════════════════════════════════════════════════
STAGING_UTILS_PATH=""
if [[ $STAGING_MODE -eq 1 ]]; then
    if command -v jq >/dev/null 2>&1; then
        :
    else
        echo "❌ FATAL: jq is required for --staging"
        exit 1
    fi

    if [[ -f "$SCRIPTS_DIR/lib/staging-utils.sh" ]]; then
        STAGING_UTILS_PATH="$SCRIPTS_DIR/lib/staging-utils.sh"
    elif [[ -f "$LOCAL_LIB_DIR/staging-utils.sh" ]]; then
        STAGING_UTILS_PATH="$LOCAL_LIB_DIR/staging-utils.sh"
    else
        echo "❌ FATAL: staging-utils.sh not found"
        exit 1
    fi

    # Set up read-only git wrapper
    REAL_GIT_PATH="$(command -v git)"
    if [[ -z "$REAL_GIT_PATH" ]]; then
        echo "❌ FATAL: git not found"
        exit 1
    fi
    export GIT_REAL_PATH="$REAL_GIT_PATH"
    export GIT_READONLY_MODE=1
    export STAGING_MODE=1

    WRAPPER_SRC=""
    if [[ -f "$SCRIPTS_DIR/lib/git-readonly-wrapper.sh" ]]; then
        WRAPPER_SRC="$SCRIPTS_DIR/lib/git-readonly-wrapper.sh"
    elif [[ -f "$LOCAL_LIB_DIR/git-readonly-wrapper.sh" ]]; then
        WRAPPER_SRC="$LOCAL_LIB_DIR/git-readonly-wrapper.sh"
    else
        echo "❌ FATAL: git-readonly-wrapper.sh not found"
        exit 1
    fi

    GIT_WRAPPER_DIR="$(mktemp -d)"
    cp "$WRAPPER_SRC" "$GIT_WRAPPER_DIR/git"
    chmod +x "$GIT_WRAPPER_DIR/git"
    export PATH="$GIT_WRAPPER_DIR:$PATH"

    echo "🔒 Staging mode active: git commit/push blocked"
fi

# ═══════════════════════════════════════════════════════════════════
# PRE-FLIGHT: UPDATE SHARED REPO CACHE
# ═══════════════════════════════════════════════════════════════════
SOURCE_REPO="$REPOS_DIR/$REPO_NAME"
LOCKFILE="$EXECUTOR_DIR/.cache-lock-$REPO_NAME"

if [[ $TEST_STAGE_ONLY -eq 0 ]]; then
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
fi

export OUTPOST_CACHE_READY=1
export GITHUB_TOKEN

# ═══════════════════════════════════════════════════════════════════
# CONTEXT INJECTION (v1.5.0)
# ═══════════════════════════════════════════════════════════════════
ENHANCED_TASK="$TASK"
INJECTION_ID=""

if [[ "$CONTEXT_LEVEL" != "off" ]]; then
    echo ""
    echo "📋 Building context injection (level: $CONTEXT_LEVEL)..."
    
    CONTEXT_OUTPUT_DIR="$EXECUTOR_DIR/runs/$BATCH_ID-context"
    mkdir -p "$CONTEXT_OUTPUT_DIR"
    
    if [[ -f "$SCRIPTS_DIR/assemble-context.sh" ]]; then
        INJECTION_ID=$("$SCRIPTS_DIR/assemble-context.sh" "$REPO_NAME" "$CONTEXT_LEVEL" "$CONTEXT_OUTPUT_DIR" 2>/dev/null || echo "")
        
        if [[ -n "$INJECTION_ID" && -f "$CONTEXT_OUTPUT_DIR/context.md" ]]; then
            CONTEXT_CONTENT=$(cat "$CONTEXT_OUTPUT_DIR/context.md")
            CONTEXT_TOKENS=$(( ${#CONTEXT_CONTENT} / 4 ))
            
            # Prepend context to task
            ENHANCED_TASK="$CONTEXT_CONTENT

<task>
$TASK
</task>"
            
            echo "   ✅ Injection ID: $INJECTION_ID"
            echo "   Tokens: ~$CONTEXT_TOKENS"
            
            # Show provenance if available
            if [[ -f "$CONTEXT_OUTPUT_DIR/context.json" ]]; then
                SECTIONS=$(python3 -c "import json; d=json.load(open('$CONTEXT_OUTPUT_DIR/context.json')); print(', '.join(d.get('sections',[])))" 2>/dev/null || echo "unknown")
                echo "   Sections: $SECTIONS"
            fi
        else
            echo "   ⚠️ Context assembly failed, proceeding without context"
        fi
    else
        echo "   ⚠️ assemble-context.sh not found, proceeding without context"
    fi
fi

# ═══════════════════════════════════════════════════════════════════
# STAGING OUTPUT HANDLER
# ═══════════════════════════════════════════════════════════════════
iso_to_epoch_ms() {
    local iso="$1"
    if [[ -z "$iso" ]]; then
        echo 0
        return
    fi
    local secs
    secs=$(date -d "$iso" +%s 2>/dev/null || echo "")
    if [[ -z "$secs" ]]; then
        echo 0
    else
        echo $(( secs * 1000 ))
    fi
}

resolve_staging_root() {
    local workspace="$1"
    local root="${STAGING_ROOT:-.staging}"
    if [[ "$root" = /* ]]; then
        echo "$root"
    else
        echo "${workspace%/}/$root"
    fi
}

stage_run_output() {
    local executor="$1"
    local run_id="$2"
    local task_summary="$3"

    if [[ -z "$executor" || -z "$run_id" ]]; then
        echo "⚠️ Staging: missing executor or run_id"
        return 0
    fi

    local run_dir="$EXECUTOR_DIR/runs/$run_id"
    local summary_path="$run_dir/summary.json"
    if [[ ! -f "$summary_path" ]]; then
        echo "⚠️ Staging: summary.json not found for $run_id"
        return 0
    fi

    local workspace
    workspace=$(jq -r '.workspace // empty' "$summary_path")
    if [[ -z "$workspace" ]]; then
        echo "⚠️ Staging: workspace missing for $run_id"
        return 0
    fi

    local staging_root
    staging_root=$(resolve_staging_root "$workspace")

    # shellcheck source=/dev/null
    source "$STAGING_UTILS_PATH"

    local status
    status=$(jq -r '.status // "unknown"' "$summary_path")
    local exit_code
    exit_code=$(jq -r '.exit_code // -1' "$summary_path")
    local started
    started=$(jq -r '.started // empty' "$summary_path")
    local completed
    completed=$(jq -r '.completed // empty' "$summary_path")

    local duration_ms=0
    if [[ -n "$started" && -n "$completed" ]]; then
        local start_ms
        local end_ms
        start_ms=$(iso_to_epoch_ms "$started")
        end_ms=$(iso_to_epoch_ms "$completed")
        if [[ "$start_ms" -gt 0 && "$end_ms" -gt 0 ]]; then
            duration_ms=$(( end_ms - start_ms ))
        fi
    fi

    local status_field="failed"
    if [[ "$status" == "success" ]]; then
        status_field="complete"
    fi

    local entry_dir
    entry_dir=$(create_staging_inbox "$run_id" "$staging_root") || return 0

    write_staging_manifest "$run_id" "$executor" "$task_summary" "$staging_root" "" "" "$executor" "$REPO_NAME"
    write_staging_status "$run_id" "$status_field" "$exit_code" "$duration_ms" "$staging_root" "$started" "$completed"

    for artifact in summary.json diff.patch task.md; do
        if [[ -f "$run_dir/$artifact" ]]; then
            cp "$run_dir/$artifact" "$entry_dir/outputs/artifacts/$artifact"
        fi
    done

    # Minimal command_result entry for audit trail (no stdout to avoid leaks)
    write_staging_entry_command_result "$entry_dir" "$executor" "" "dispatch-$executor" "$exit_code" "" ""
}

if [[ "${OUTPOST_TEST_MODE:-0}" == "1" && "${OUTPOST_TEST_STAGE_ONLY:-0}" == "1" ]]; then
    if [[ $STAGING_MODE -ne 1 ]]; then
        echo "❌ TEST MODE: --staging required"
        exit 1
    fi
    if [[ -z "${OUTPOST_TEST_RUN_DIR:-}" || -z "${OUTPOST_TEST_EXECUTOR:-}" || -z "${OUTPOST_TEST_RUN_ID:-}" ]]; then
        echo "❌ TEST MODE: OUTPOST_TEST_RUN_DIR, OUTPOST_TEST_EXECUTOR, OUTPOST_TEST_RUN_ID required"
        exit 1
    fi
    EXECUTOR_DIR="${OUTPOST_TEST_RUN_DIR%/}"
    stage_run_output "$OUTPOST_TEST_EXECUTOR" "$OUTPOST_TEST_RUN_ID" "${OUTPOST_TEST_TASK_SUMMARY:-TEST}"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════
# DISPATCH TO AGENTS
# ═══════════════════════════════════════════════════════════════════
IFS=',' read -ra EXEC_ARRAY <<< "$EXECUTORS"
EXEC_COUNT=${#EXEC_ARRAY[@]}

if [[ $EXEC_COUNT -gt 1 ]]; then
    echo ""
    echo "🔀 Parallel execution ($EXEC_COUNT agents, isolated workspaces)"
fi

run_with_capture() {
    local log_file="$1"
    local status_file="$2"
    shift 2
    bash -c 'set -o pipefail; "$@" 2>&1 | tee "$0"; echo ${PIPESTATUS[0]} > "$1"' "$log_file" "$status_file" "$@"
}

PIDS=()
EXEC_ORDER=()
LOG_FILES=()
STATUS_FILES=()

for executor in "${EXEC_ARRAY[@]}"; do
    executor=$(echo "$executor" | xargs)
    echo ""
    echo "📤 Dispatching to $executor..."

    log_file="$(mktemp "/tmp/outpost-${BATCH_ID}-${executor}.log.XXXXXX")"
    status_file="$(mktemp "/tmp/outpost-${BATCH_ID}-${executor}.status.XXXXXX")"
    # Make temp files writable by subprocesses (fix permission denied in bash -c context)
    chmod 644 "$log_file" "$status_file" 2>/dev/null || true

    case "$executor" in
        claude)
            run_with_capture "$log_file" "$status_file" "$EXECUTOR_DIR/dispatch.sh" "$REPO_NAME" "$ENHANCED_TASK" &
            ;;
        codex)
            run_with_capture "$log_file" "$status_file" "$EXECUTOR_DIR/dispatch-codex.sh" "$REPO_NAME" "$ENHANCED_TASK" &
            ;;
        gemini)
            run_with_capture "$log_file" "$status_file" "$EXECUTOR_DIR/dispatch-gemini.sh" "$REPO_NAME" "$ENHANCED_TASK" &
            ;;
        aider)
            run_with_capture "$log_file" "$status_file" "$EXECUTOR_DIR/dispatch-aider.sh" "$REPO_NAME" "$ENHANCED_TASK" &
            ;;
        grok)
            run_with_capture "$log_file" "$status_file" "$EXECUTOR_DIR/dispatch-grok.sh" "$REPO_NAME" "$ENHANCED_TASK" &
            ;;
        *)
            echo "⚠️ Unknown executor: $executor"
            rm -f "$log_file" "$status_file"
            continue
            ;;
    esac

    PIDS+=($!)
    EXEC_ORDER+=("$executor")
    LOG_FILES+=("$log_file")
    STATUS_FILES+=("$status_file")
done

if [[ ${#PIDS[@]} -gt 0 ]]; then
    echo ""
    echo "⏳ Waiting for all agents..."
    for pid in "${PIDS[@]}"; do
        wait $pid
    done
fi

if [[ $STAGING_MODE -eq 1 ]]; then
    echo ""
    echo "📦 Writing staging outputs..."
    for i in "${!EXEC_ORDER[@]}"; do
        executor="${EXEC_ORDER[$i]}"
        log_file="${LOG_FILES[$i]}"
        run_id="$(awk -F ': ' '/^Run ID: / {print $2; exit}' "$log_file" 2>/dev/null || true)"
        if [[ -z "$run_id" ]]; then
            echo "⚠️ Staging: Run ID not found for $executor"
            continue
        fi
        stage_run_output "$executor" "$run_id" "$TASK_SUMMARY"
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ UNIFIED DISPATCH COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo "Batch: $BATCH_ID"
[[ -n "$INJECTION_ID" ]] && echo "Context: $INJECTION_ID"
echo "Use 'list-runs.sh' to see results"
echo "Use 'promote-workspace.sh <run-id>' to push changes"
