# Outpost

**Multi-agent headless executor for AI-powered code tasks.**

Outpost enables Claude UI to dispatch coding tasks to remote servers running AI coding agents (Claude Code and OpenAI Codex), bridging conversational AI with hands-on code execution.

## Architecture

```
┌─────────────────────────────────────────────────┐
│              CLAUDE UI (Orchestrator)           │
│           AWS SSM SendCommand                   │
└───────────┬───────────────────┬─────────────────┘
            │                   │
            ▼                   ▼
    ┌───────────────┐   ┌───────────────┐
    │ dispatch.sh   │   │ dispatch-     │
    │ Claude Code   │   │ codex.sh      │
    │               │   │ OpenAI Codex  │
    └───────┬───────┘   └───────┬───────┘
            │                   │
            └─────────┬─────────┘
                      ▼
    ┌─────────────────────────────────────────────┐
    │           SHARED INFRASTRUCTURE             │
    │   repos/ (cloned repos)                     │
    │   runs/  (execution artifacts)              │
    │   Git credentials (push capability)         │
    └─────────────────────────────────────────────┘
```

## Executors

| Executor | Model | Subscription | Dispatcher |
|----------|-------|--------------|------------|
| Claude Code | claude-sonnet-4-20250514 | Claude Max | dispatch.sh |
| OpenAI Codex | gpt-5.2-codex | ChatGPT Plus | dispatch-codex.sh |

## Quick Start

### Dispatch a Task (Claude Code)

```bash
aws ssm send-command \
  --instance-ids "mi-0d77bfe39f630bd5c" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch.sh swords-of-chaos-reborn \"Fix the bug in server.js\""]'
```

### Dispatch a Task (OpenAI Codex)

```bash
aws ssm send-command \
  --instance-ids "mi-0d77bfe39f630bd5c" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-codex.sh swords-of-chaos-reborn \"Fix the bug in server.js\""]'
```

### Get Results

```bash
# List recent runs
sudo -u ubuntu /home/ubuntu/claude-executor/scripts/list-runs.sh

# Get specific run
sudo -u ubuntu /home/ubuntu/claude-executor/scripts/get-results.sh <run-id> all
```

### Push Changes

```bash
sudo -u ubuntu /home/ubuntu/claude-executor/scripts/push-changes.sh <repo> "commit message"
```

## Run Artifacts

Each run creates:

```
runs/<run-id>/
├── task.md          # Original task
├── output.log       # Agent stdout/stderr
├── summary.json     # Metadata (executor, status, sha)
└── diff.patch       # Git changes (if any)
```

## Authentication

Both agents use subscription-based auth (no API charges):

| Agent | Auth File | Source |
|-------|-----------|--------|
| Claude Code | ~/.claude/.credentials.json | macOS Keychain transfer |
| OpenAI Codex | ~/.codex/auth.json | File-based on both platforms |

## Multi-Agent Use Cases

1. **Comparison** - Same task to both, compare results
2. **Parallel** - Race for fastest solution
3. **Specialization** - Route by task type
4. **Fallback** - Redundancy if one rate-limits
5. **Cost optimization** - Use cheaper model when adequate

## Scripts

| Script | Purpose |
|--------|---------|
| dispatch.sh | Claude Code executor |
| dispatch-codex.sh | OpenAI Codex executor |
| get-results.sh | Retrieve run outputs |
| push-changes.sh | Commit and push changes |
| list-runs.sh | List recent runs |

## Server Details

| Component | Value |
|-----------|-------|
| Server | SOC (52.44.78.2) |
| SSM Instance | mi-0d77bfe39f630bd5c |
| Executor Path | /home/ubuntu/claude-executor/ |
| Region | us-east-1 |

## Cost Model

| Service | Monthly | Includes |
|---------|---------|----------|
| Claude Max | $100 | Unlimited Claude Code |
| ChatGPT Plus | $20 | Unlimited Codex |
| **Total** | **$120** | Two AI executors |

## Future

- [ ] Unified dispatcher with `--executor` flag
- [ ] Parallel execution (`--executor both`)
- [ ] Comparison tooling
- [ ] Gemini CLI integration
- [ ] S3 storage for large outputs
