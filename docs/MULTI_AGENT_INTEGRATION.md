# Outpost: Multi-Agent Integration Guide

## Executive Summary

Outpost is a multi-agent headless executor system that enables Claude UI to dispatch coding tasks to remote servers running multiple AI coding agents in parallel.

**Fleet Status:** OPERATIONAL (4/4 agents)

| Agent | Model | Status | Auth Method |
|-------|-------|--------|-------------|
| Claude Code | claude-opus-4-5-20251101 | ✅ Active | Claude Max subscription ($100/mo) |
| OpenAI Codex | gpt-5.2-codex | ✅ Active | ChatGPT Plus subscription ($20/mo) |
| Gemini CLI | gemini-3-pro-preview | ✅ Active | Gemini AI Ultra subscription ($50/mo) |
| Aider | deepseek/deepseek-coder | ✅ Active | DeepSeek API (~$0.14/MTok) |

---

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                        Claude UI                                   │
│                    (Orchestrator Role)                             │
└───────────────────────────────────────────────────────────────────┘
                              │
                     AWS SSM SendCommand
                              │
                              ▼
┌───────────────────────────────────────────────────────────────────┐
│                    SOC Server (52.44.78.2)                         │
│                                                                     │
│   dispatch-unified.sh                                               │
│        │                                                            │
│        ├─→ dispatch.sh        → Claude Code (Opus 4.5)             │
│        ├─→ dispatch-codex.sh  → OpenAI Codex (GPT-5.2)             │
│        ├─→ dispatch-gemini.sh → Gemini CLI (Gemini 3 Pro)          │
│        └─→ dispatch-aider.sh  → Aider (DeepSeek Coder)             │
│                                                                     │
│   Each agent runs in isolated workspace (true parallelism)          │
└───────────────────────────────────────────────────────────────────┘
```

---

## Use Cases

| Scenario | Recommended Executor | Why |
|----------|---------------------|-----|
| Complex architecture | `--executor=claude` | Best reasoning, multi-file changes |
| Code generation | `--executor=codex` | Fast, focused code output |
| Documentation | `--executor=gemini` | Strong at prose and analysis |
| High-volume tasks | `--executor=aider` | Cheapest per-token cost |
| Second opinion | `--executor=claude,codex` | Compare approaches |
| Consensus/review | `--executor=all` | Four perspectives |

---

## Invocation

### From Claude UI

```bash
aws ssm send-command \
  --instance-ids "mi-0d77bfe39f630bd5c" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <repo> \"<task>\" --executor=<agent>"]' \
  --query 'Command.CommandId' \
  --output text
```

### Get Results

```bash
aws ssm get-command-invocation \
  --command-id "<COMMAND_ID>" \
  --instance-id "mi-0d77bfe39f630bd5c" \
  --query 'StandardOutputContent' \
  --output text
```

---

## Adding a New Agent

1. Create `dispatch-newagent.sh` following existing pattern
2. Add case in `dispatch-unified.sh` EXECUTORS switch
3. Update this document and README.md
4. Test with `--executor=newagent`

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| GITHUB_TOKEN not set | .env not loaded | Check /home/ubuntu/claude-executor/.env |
| Git clone failed | Invalid repo name | Verify repo exists in rgsuarez/ |
| Timeout | Agent took > 10min | Increase AGENT_TIMEOUT in .env |
| dubious ownership | Git safe.directory | Run as ubuntu user via sudo |

---

*Outpost v1.4 Multi-Agent Integration Guide*
