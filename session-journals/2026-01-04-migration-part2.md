---
type: session
project: outpost
status: active
started: 2026-01-04T22:00:00Z
---

# Session: Infrastructure Migration Part 2 (Tasks 3-9)

---
type: checkpoint
timestamp: 2026-01-04T22:17:00Z
note: "Task 3 complete - dependencies installed"
---

## Work Since Last Save

### Actions Taken
- Verified/installed dependencies on outpost-prod (mi-0bbd8fed3f0650ddb)
- Confirmed all required packages present

### Decisions Made
- Accepted Node 18.19.1 (Ubuntu 24.04 default LTS) vs Node 20 — rationale: LTS sufficient for agent CLIs, avoids PPA complexity

### Commands Executed
```bash
aws ssm send-command \
  --profile soc \
  --instance-ids "mi-0bbd8fed3f0650ddb" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["git --version && node -v && npm -v && python3 --version && aws --version"]'
```

### Versions Confirmed
| Package | Version |
|---------|---------|
| git | 2.43.0 |
| node | 18.19.1 |
| npm | 9.2.0 |
| python | 3.12.3 |
| aws-cli | 2.32.28 |

### Current Focus
Task 4: Install agent CLIs (claude-code, codex, gemini, aider)

---
type: checkpoint
timestamp: 2026-01-05T01:45:00Z
note: "Task 4 complete - all 4 agent CLIs installed"
---

## Work Since Last Save

### Actions Taken
- Fixed Task 3 journal entry to comply with zeOS standards (YAML frontmatter, Delta Rule format)
- Installed Claude Code CLI via npm (@anthropic-ai/claude-code)
- Installed Codex CLI via npm (@openai/codex)
- Installed Gemini CLI via npm (@google/gemini-cli)
- Installed Aider via pipx as ubuntu user (aider-chat)

### Decisions Made
- Used pipx for Aider instead of pip3 — rationale: pip3 install failed due to SSM running as root, pipx creates isolated environment for ubuntu user
- Found correct Gemini package by inspecting SOC server symlink (@google/gemini-cli not @anthropic-ai/gemini-cli)

### Commands Executed
```bash
# Install npm-based CLIs
aws ssm send-command --profile soc --instance-ids "mi-0bbd8fed3f0650ddb" \
  --parameters 'commands=["npm install -g @anthropic-ai/claude-code", "npm install -g @openai/codex", "npm install -g @google/gemini-cli"]'

# Install Aider via pipx
aws ssm send-command --profile soc --instance-ids "mi-0bbd8fed3f0650ddb" \
  --parameters 'commands=["apt-get install -y pipx", "sudo -u ubuntu pipx install aider-chat"]'
```

### CLIs Installed
| Agent | Path | Install Method |
|-------|------|----------------|
| claude | /usr/local/bin/claude | npm global |
| codex | /usr/local/bin/codex | npm global |
| gemini | /usr/local/bin/gemini | npm global |
| aider | /home/ubuntu/.local/bin/aider | pipx (ubuntu user) |

### Current Focus
Task 5: Clone dispatch scripts from outpost repo
