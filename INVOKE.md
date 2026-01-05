# Outpost Invocation Guide

**Landing file for invoking Outpost agents. Copy-paste ready.**

---

## Prerequisites

```yaml
AWS_PROFILE: soc
REGION: us-east-1
SSM_INSTANCE: mi-0bbd8fed3f0650ddb
EXECUTOR_PATH: /home/ubuntu/claude-executor/
```

---

## Single Agent

### Claude Code (Opus 4.5)

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <REPO> \"<TASK>\" --executor=claude"]' \
  --query 'Command.CommandId' --output text
```

### OpenAI Codex

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <REPO> \"<TASK>\" --executor=codex"]' \
  --query 'Command.CommandId' --output text
```

### Gemini CLI

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <REPO> \"<TASK>\" --executor=gemini"]' \
  --query 'Command.CommandId' --output text
```

### Aider (DeepSeek)

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <REPO> \"<TASK>\" --executor=aider"]' \
  --query 'Command.CommandId' --output text
```

---

## All Agents (Parallel)

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh <REPO> \"<TASK>\" --executor=all"]' \
  --query 'Command.CommandId' --output text
```

---

## With Context Injection

Add `--context` to enable zeOS knowledge injection:

```bash
# Standard context (~1200 tokens)
--executor=claude --context

# Minimal context (~600 tokens)
--executor=claude --context=minimal

# Full context (~1800 tokens)
--executor=claude --context=full
```

Example:

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/dispatch-unified.sh swords-of-chaos-reborn \"Add PARTY command\" --executor=claude --context=standard"]' \
  --query 'Command.CommandId' --output text
```

---

## Get Results

Wait 30-90 seconds (depending on task), then:

```bash
aws ssm get-command-invocation --profile soc \
  --command-id "<COMMAND_ID>" \
  --instance-id "mi-0bbd8fed3f0650ddb" \
  --query 'StandardOutputContent' --output text
```

Or check status only:

```bash
aws ssm get-command-invocation --profile soc \
  --command-id "<COMMAND_ID>" \
  --instance-id "mi-0bbd8fed3f0650ddb" \
  --query 'Status' --output text
```

---

## List Recent Runs

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/scripts/list-runs.sh"]' \
  --query 'Command.CommandId' --output text
```

---

## Promote Changes

After a successful run with code changes:

```bash
aws ssm send-command --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo -u ubuntu /home/ubuntu/claude-executor/scripts/promote-workspace.sh <RUN_ID> \"Commit message\" --push"]' \
  --query 'Command.CommandId' --output text
```

---

## Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `<REPO>` | GitHub repo name (without org) | `swords-of-chaos-reborn` |
| `<TASK>` | Natural language task description | `Add error handling to login` |
| `<COMMAND_ID>` | UUID from send-command output | `b174d88d-594c-4cc7-...` |
| `<RUN_ID>` | Run directory name | `20260105-035934-5z4vyq` |

---

## Agent Comparison

| Agent | Best For | Cost |
|-------|----------|------|
| Claude | Complex reasoning, architecture, multi-file | $100/mo |
| Codex | Code generation, refactoring | $20/mo |
| Gemini | Analysis, documentation | $50/mo |
| Aider | Iterative editing, low-cost tasks | ~$0.14/MTok |

---

*Outpost v1.6.0 — Read OUTPOST_INTERFACE.md for full API spec*
