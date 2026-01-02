# Outpost

**Multi-Agent Headless Executor System**

Outpost enables Claude UI sessions to dispatch coding tasks to remote servers running multiple AI coding agents in parallel.

## Fleet Status

| Agent | Model | Status | Dispatcher |
|-------|-------|--------|------------|
| Claude Code | claude-sonnet-4 | ✅ Active | `dispatch.sh` |
| OpenAI Codex | gpt-5.2-codex | ✅ Active | `dispatch-codex.sh` |
| Gemini CLI | gemini-2.5-pro | ✅ Active | `dispatch-gemini.sh` |

## Architecture

```
Claude UI (Orchestrator) → AWS SSM SendCommand
    ↓                    ↓                    ↓
dispatch.sh      dispatch-codex.sh    dispatch-gemini.sh
(Claude Code)    (OpenAI Codex)       (Gemini CLI)
    ↓                    ↓                    ↓
        Shared Infrastructure
        (repos/, runs/, git credentials)
```

## Quick Start

```bash
# Dispatch to Claude Code
aws ssm send-command \
  --instance-ids "mi-0d77bfe39f630bd5c" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch.sh repo-name \"task\""]'

# Dispatch to OpenAI Codex
aws ssm send-command ... 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-codex.sh repo-name \"task\""]'

# Dispatch to Gemini CLI
aws ssm send-command ... 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-gemini.sh repo-name \"task\""]'
```

## Cost Model

| Service | Monthly | Notes |
|---------|---------|-------|
| Claude Max | $100 | Unlimited Claude Code |
| ChatGPT Plus | $20 | Unlimited Codex CLI |
| Google AI Ultra | ~$50 | Highest Gemini limits |
| **Total** | **$170** | Three AI executors, no API charges |

## Documentation

- [Multi-Agent Integration Guide](docs/MULTI_AGENT_INTEGRATION.md) - Complete setup and usage
- [Outpost Soul](docs/OUTPOST_SOUL.md) - zeOS integration

## Scripts

| Script | Purpose |
|--------|---------|
| `dispatch.sh` | Execute task via Claude Code |
| `dispatch-codex.sh` | Execute task via OpenAI Codex |
| `dispatch-gemini.sh` | Execute task via Gemini CLI |
| `get-results.sh` | Retrieve run outputs |
| `list-runs.sh` | List recent runs |
| `push-changes.sh` | Commit and push approved changes |

## Server

- **Host:** SOC (52.44.78.2)
- **SSM Instance:** mi-0d77bfe39f630bd5c
- **Region:** us-east-1

## License

Private - Zero Echelon LLC
