# Outpost: OpenAI Codex Integration Scope

## Executive Summary

**Objective:** Add OpenAI Codex as a second executor in Outpost, enabling multi-agent dispatch from Claude UI.

**Feasibility:** HIGH - Same pattern as Claude Code, nearly identical architecture.

**Subscription Model:** ChatGPT Plus ($20/mo) includes Codex CLI - no API charges.

---

## Comparison: Claude Code vs OpenAI Codex

| Aspect | Claude Code | OpenAI Codex |
|--------|-------------|--------------|
| Install | `npm i -g @anthropic-ai/claude-code` | `npm i -g @openai/codex` |
| Version | 2.0.76 | Latest from npm |
| Subscription | Claude Pro/Max | ChatGPT Plus/Pro/Business |
| Headless Command | `claude -p "task"` | `codex exec "task"` |
| Skip Approvals | `--dangerously-skip-permissions` | `--full-auto` or `--dangerously-bypass-approvals-and-sandbox` |
| Output | stdout/stderr | stdout/stderr |
| JSON Output | `--output-format json` | `--json` |
| Config Location | `~/.claude/` | `~/.codex/` |
| Credentials | `~/.claude/.credentials.json` | Keyring + `~/.codex/config.toml` |
| Auth Challenge | OAuth → token transfer | OAuth → token transfer OR API key |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              CLAUDE UI (Orchestrator)                           │
└───────────┬─────────────────┬───────────────────────────────────┘
            │                 │
            ▼                 ▼
    ┌───────────────┐ ┌───────────────┐
    │ dispatch.sh   │ │ dispatch-     │
    │ (Claude Code) │ │ codex.sh      │
    │               │ │ (OpenAI Codex)│
    └───────┬───────┘ └───────┬───────┘
            │                 │
            ▼                 ▼
    ┌─────────────────────────────────────┐
    │        SHARED INFRASTRUCTURE        │
    │  - repos/                           │
    │  - runs/                            │
    │  - Git credentials                  │
    └─────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Install & Auth (30 min)

#### 1.1 Install Codex CLI
```bash
npm install -g @openai/codex
codex --version
```

#### 1.2 Authentication Options

**Option A: API Key (Simplest for headless)**
```bash
# Set API key as environment variable
export OPENAI_API_KEY="sk-..."

# Or login with API key
echo "$OPENAI_API_KEY" | codex login --with-api-key
```

**Option B: Subscription Token Transfer (No API charges)**

Same pattern as Claude Code:
1. Login on Mac: `codex` → OAuth in browser
2. Find credentials (likely in Keychain or `~/.codex/`)
3. Transfer to server

#### 1.3 Credentials Location Research
```bash
# On Mac after login, check:
ls -la ~/.codex/
security find-generic-password -s "codex" -w 2>/dev/null
find ~ -name "*codex*" -type f 2>/dev/null | head -20
```

---

### Phase 2: Dispatch Script (30 min)

#### 2.1 Create dispatch-codex.sh

```bash
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

# Codex exec with full-auto and sandbox write access
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
```

---

### Phase 3: Unified Dispatcher (Optional Enhancement)

Create a single `dispatch.sh` that accepts executor as parameter:

```bash
# Usage:
./dispatch.sh --executor claude swords-of-chaos-reborn "Fix bug"
./dispatch.sh --executor codex swords-of-chaos-reborn "Fix bug"
./dispatch.sh --executor both swords-of-chaos-reborn "Fix bug"  # Parallel!
```

---

## Authentication Deep Dive

### API Key Path (Recommended for MVP)

**Pros:**
- Simple to set up
- Works immediately on headless
- No token transfer needed

**Cons:**
- Uses API credits (pay-per-use)
- Need to manage API key security

**Setup:**
```bash
# Create API key at: https://platform.openai.com/api-keys
# Store securely
echo "OPENAI_API_KEY=sk-..." >> ~/.codex/.env
```

### Subscription Path (No API charges)

**Pros:**
- Included in ChatGPT Plus ($20/mo)
- No per-use charges

**Cons:**
- OAuth token transfer complexity
- May need periodic refresh

**Research needed:**
- Where does Codex store OAuth tokens on Linux?
- Can we use the same Keychain extraction trick?
- What's the token refresh frequency?

---

## Parallel Execution Potential

With both Claude Code and Codex available:

```bash
# Same task, different agents - race!
./dispatch.sh --executor claude repo "Fix the bug" &
./dispatch.sh --executor codex repo "Fix the bug" &
wait

# Compare outputs
diff runs/*/diff.patch
```

**Use cases:**
1. **Consensus** - Both agree? High confidence fix.
2. **Best-of-N** - Take the better solution.
3. **Specialization** - Route to agent based on task type.
4. **Fallback** - If one fails/rate-limits, use other.

---

## Security Considerations

| Concern | Claude Code | Codex | Mitigation |
|---------|-------------|-------|------------|
| Credentials | Token file 600 | API key env | File perms, secrets manager |
| Rate limits | Subscription tier | Subscription/API tier | Monitor, fallback |
| Code access | Git clone | Git clone | PAT with minimal scope |
| Network | Full | Sandbox configurable | Use sandbox defaults |

---

## Cost Analysis

### Subscription Model (Recommended)
| Service | Cost | Includes |
|---------|------|----------|
| Claude Max | $100/mo | Claude Code unlimited |
| ChatGPT Plus | $20/mo | Codex CLI included |
| **Total** | **$120/mo** | Both executors, no metering |

### API Model (Alternative)
| Service | Cost | Notes |
|---------|------|-------|
| Claude API | ~$15/MTok | Per-use |
| OpenAI API | ~$15/MTok | Per-use |
| Variable | Depends on usage | Can spike |

**Recommendation:** Subscription model. Predictable costs, unlimited usage within tier limits.

---

## Implementation Checklist

### MVP (2 hours)
- [ ] Install Codex CLI on SOC server
- [ ] Configure API key auth (faster than OAuth)
- [ ] Create dispatch-codex.sh
- [ ] Test simple task
- [ ] Update get-results.sh to show executor type

### Enhancement (2 hours)
- [ ] Research subscription auth for Codex
- [ ] Create unified dispatch.sh with --executor flag
- [ ] Add parallel execution capability
- [ ] Update list-runs.sh to filter by executor

### Future
- [ ] Add Gemini CLI (if/when available)
- [ ] Build agent routing logic
- [ ] Create comparison tooling
- [ ] Dashboard for multi-agent runs

---

## Decision Points

### Q1: API Key vs Subscription Auth?

**Recommendation:** Start with API key for speed. Subscription auth can be added later.

If you have a ChatGPT Plus subscription and want to avoid API charges, we can research the OAuth token location after MVP works.

### Q2: Separate scripts or unified dispatcher?

**Recommendation:** Start with `dispatch-codex.sh` alongside existing `dispatch.sh`. Unify later once patterns stabilize.

### Q3: Do you have a ChatGPT Plus subscription?

This determines whether we use subscription auth (free) or API key (metered).

---

## Next Steps

1. **Confirm:** Do you have ChatGPT Plus or an OpenAI API key?
2. **Install:** Deploy Codex CLI to SOC server
3. **Auth:** Configure whichever auth method you prefer
4. **Test:** Run parallel Claude vs Codex on same task
5. **Iterate:** Refine based on results

---

## Appendix: Codex CLI Quick Reference

```bash
# Interactive mode
codex

# Non-interactive (headless)
codex exec "task description"

# Full automation (no prompts)
codex exec --full-auto "task"

# Nuclear option (bypass everything)
codex exec --dangerously-bypass-approvals-and-sandbox "task"

# With sandbox write access
codex exec --full-auto --sandbox workspace-write "task"

# JSON output
codex exec --json "task"

# Resume previous session
codex exec resume --last "follow-up"

# Login with API key
echo "$OPENAI_API_KEY" | codex login --with-api-key

# Check auth status
codex login status
```
