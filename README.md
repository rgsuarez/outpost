# Outpost

**Multi-Agent Headless Executor System**

Outpost enables Claude UI sessions to dispatch coding tasks to remote servers running multiple AI coding agents in parallel.

## Fleet Status

| Agent | Model | Status | Dispatcher |
|-------|-------|--------|------------|
| Claude Code | **claude-opus-4-5** | ✅ Active | `dispatch.sh` |
| OpenAI Codex | gpt-5.2-codex | ✅ Active | `dispatch-codex.sh` |
| Gemini CLI | **gemini-3-pro** | ✅ Active | `dispatch-gemini.sh` |

## Architecture

```
Claude UI (Orchestrator) → AWS SSM SendCommand
    ↓                    ↓                    ↓
dispatch.sh      dispatch-codex.sh    dispatch-gemini.sh
(Opus 4.5)       (Codex)              (Gemini 3 Pro)
    ↓                    ↓                    ↓
        Shared Infrastructure
        (repos/, runs/, git credentials)
```

## Quick Start

```bash
# Dispatch to Claude Code (Opus 4.5)
aws ssm send-command \
  --instance-ids "mi-0d77bfe39f630bd5c" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch.sh repo-name \"task\""]'

# Dispatch to OpenAI Codex
aws ssm send-command ... 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-codex.sh repo-name \"task\""]'

# Dispatch to Gemini CLI (Gemini 3 Pro)
aws ssm send-command ... 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-gemini.sh repo-name \"task\""]'
```

## Cost Model

| Service | Monthly | Notes |
|---------|---------|-------|
| Claude Max | $100 | Unlimited Claude Code (Opus 4.5) |
| ChatGPT Plus | $20 | Unlimited Codex CLI |
| Google AI Ultra | ~$50 | Gemini 3 Pro access |
| **Total** | **$170** | Three top-tier AI executors |

## Documentation

- [Multi-Agent Integration Guide](docs/MULTI_AGENT_INTEGRATION.md)
- [Outpost Soul](docs/OUTPOST_SOUL.md)

## Scripts

| Script | Agent | Model |
|--------|-------|-------|
| `dispatch.sh` | Claude Code | claude-opus-4-5-20251101 |
| `dispatch-codex.sh` | OpenAI Codex | gpt-5.2-codex |
| `dispatch-gemini.sh` | Gemini CLI | gemini-3-pro-preview |
| `get-results.sh` | - | Retrieve outputs |
| `list-runs.sh` | - | List runs |
| `push-changes.sh` | - | Commit changes |

## Server

- **Host:** SOC (52.44.78.2)
- **SSM Instance:** mi-0d77bfe39f630bd5c
- **Region:** us-east-1

## License

Private - Zero Echelon LLC
