#!/bin/bash
# dispatch-unified.sh - Unified multi-agent dispatcher for Outpost v1.2
# Enables single, multiple, or all-agent execution from one command

# Don't use set -e globally - handle errors explicitly

REPO_NAME="${1:-}"
TASK="${2:-}"
EXECUTOR="${3:---executor=claude}"  # Default to claude

# Parse --executor flag
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
    echo "Executors:"
    echo "  claude    - Claude Code (Opus 4.5)"
    echo "  codex     - OpenAI Codex (GPT-5.2)"
    echo "  gemini    - Gemini CLI (Gemini 3 Pro)"
    echo "  aider     - Aider (DeepSeek Coder)"
    echo "  all       - All four agents in parallel"
    echo ""
    echo "Multiple agents: --executor=claude,gemini,aider"
    echo ""
    echo "Examples:"
    echo "  dispatch-unified.sh soc-reborn \"count files\" --executor=claude"
    echo "  dispatch-unified.sh soc-reborn \"count files\" --executor=claude,aider"
    echo "  dispatch-unified.sh soc-reborn \"count files\" --executor=all"
    exit 1
fi

EXECUTOR_DIR="/home/ubuntu/claude-executor"
BATCH_ID="$(date +%Y%m%d-%H%M%S)-batch-$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)"

echo "═══════════════════════════════════════════════════════════════"
echo "🚀 OUTPOST UNIFIED DISPATCH"
echo "═══════════════════════════════════════════════════════════════"
echo "Batch ID:   $BATCH_ID"
echo "Repo:       $REPO_NAME"
echo "Task:       $TASK"
echo "Executors:  $EXECUTORS"
echo "═══════════════════════════════════════════════════════════════"

# Expand "all" to full list
if [[ "$EXECUTORS" == "all" ]]; then
    EXECUTORS="claude,codex,gemini,aider"
fi

# Track PIDs for parallel execution
declare -a PIDS
declare -a AGENTS

# Function to dispatch to a single agent
dispatch_agent() {
    local agent=$1
    local script=""
    
    case $agent in
        claude)
            script="dispatch.sh"
            ;;
        codex)
            script="dispatch-codex.sh"
            ;;
        gemini)
            script="dispatch-gemini.sh"
            ;;
        aider)
            script="dispatch-aider.sh"
            ;;
        *)
            echo "❌ Unknown executor: $agent"
            return 1
            ;;
    esac
    
    echo "📤 Dispatching to $agent..."
    # Run with error capture - don't let failures propagate
    "$EXECUTOR_DIR/$script" "$REPO_NAME" "$TASK" 2>&1 || {
        echo "⚠️ $agent dispatch returned non-zero exit code"
    }
}

# Split executors by comma and run
IFS=',' read -ra AGENT_ARRAY <<< "$EXECUTORS"

if [[ ${#AGENT_ARRAY[@]} -eq 1 ]]; then
    # Single agent - run synchronously
    dispatch_agent "${AGENT_ARRAY[0]}"
else
    # Multiple agents - run in parallel
    echo ""
    echo "🔀 Parallel execution mode (${#AGENT_ARRAY[@]} agents)"
    echo ""
    
    for agent in "${AGENT_ARRAY[@]}"; do
        dispatch_agent "$agent" &
        PIDS+=($!)
        AGENTS+=("$agent")
    done
    
    # Wait for all to complete
    echo ""
    echo "⏳ Waiting for all agents to complete..."
    
    FAILED=0
    for i in "${!PIDS[@]}"; do
        if wait "${PIDS[$i]}"; then
            echo "✅ ${AGENTS[$i]} completed"
        else
            echo "❌ ${AGENTS[$i]} failed"
            FAILED=$((FAILED + 1))
        fi
    done
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 BATCH COMPLETE: $BATCH_ID"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Agents run: ${#AGENT_ARRAY[@]}"
    echo "Succeeded:  $((${#AGENT_ARRAY[@]} - FAILED))"
    echo "Failed:     $FAILED"
    echo ""
    echo "View results: ls -la $EXECUTOR_DIR/runs/ | tail -${#AGENT_ARRAY[@]}"
    echo "═══════════════════════════════════════════════════════════════"
fi
