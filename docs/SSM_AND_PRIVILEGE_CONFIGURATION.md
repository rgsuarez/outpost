# SSM and Privilege Configuration

**Last Updated:** 2026-01-09
**Version:** Outpost v1.8+

## Overview

This document describes the SSM agent keepalive configuration and privilege dropping architecture implemented in Outpost to ensure reliable operation and security when running AI agents via AWS Systems Manager.

---

## Problem Statement

### Root Causes Identified

1. **SSM Agent Crashes**: SSM agent would crash and not restart automatically, causing "ConnectionLost" status and requiring manual instance reboots
2. **Root Execution**: SSM commands run as root by default (AWS architectural constraint), causing:
   - Claude Code security refusals (`--dangerously-skip-permissions cannot be used with root`)
   - File ownership issues (files created as root:root instead of ubuntu:ubuntu)
   - Permission denied errors in subprocess contexts

### Impact

- **Outpost server offline**: 6+ hour downtime when SSM agent crashed
- **Blueprint generation failures**: Permission denied on temp files (`/tmp/.../claude.status`)
- **Operational friction**: Agents had to "figure out" privilege issues on every invocation, adding delay

---

## Solution 1: SSM Agent Auto-Restart

### Configuration

Configured systemd to automatically restart the SSM agent on both Outpost and SOC servers.

#### Service Override Location

```
/etc/systemd/system/snap.amazon-ssm-agent.amazon-ssm-agent.service.d/restart.conf
```

#### Configuration Content

```ini
[Service]
Restart=always
RestartSec=10s
```

#### Deployment Command

```bash
# For Outpost server (Lightsail instance, snap-based SSM)
aws ssm send-command \
  --instance-ids mi-0bbd8fed3f0650ddb \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["mkdir -p /etc/systemd/system/snap.amazon-ssm-agent.amazon-ssm-agent.service.d && cat > /etc/systemd/system/snap.amazon-ssm-agent.amazon-ssm-agent.service.d/restart.conf << '\''EOF'\''
[Service]
Restart=always
RestartSec=10s
EOF
systemctl daemon-reload && systemctl restart snap.amazon-ssm-agent.amazon-ssm-agent.service"]' \
  --profile soc
```

#### For SOC Server

Same configuration applied to SOC server (mi-0d77bfe39f630bd5c) for consistency.

### Benefits

- SSM agent automatically restarts on crash within 10 seconds
- Prevents multi-hour downtime requiring manual intervention
- Survives instance reboots (systemd override persists)
- Standard industry pattern for service resilience

### Verification

```bash
# Check restart configuration
systemctl show snap.amazon-ssm-agent.amazon-ssm-agent.service | grep -E "^Restart="

# Expected output:
# Restart=always
```

---

## Solution 2: Automatic Privilege Dropping

### Architecture

All dispatch scripts automatically drop from root to ubuntu user when invoked via SSM.

#### Implementation Pattern

Two different patterns depending on script type:

##### Pattern A: Leaf Scripts (exec-based)

Used in: `dispatch.sh`, `dispatch-aider.sh`, `dispatch-codex.sh`, `dispatch-gemini.sh`, `dispatch-grok.sh`

```bash
#!/bin/bash
# Source environment if available
[[ -f /home/ubuntu/claude-executor/.env ]] && source /home/ubuntu/claude-executor/.env

# AUTO-PRIVILEGE DROP: Ensure execution as ubuntu user
if [[ $EUID -eq 0 ]]; then
    echo "🔒 Auto-dropping privileges from root to ubuntu user..."
    exec sudo -u ubuntu -E HOME=/home/ubuntu bash "$0" "$@"
fi

# Rest of script continues as ubuntu user...
```

**Why exec?** These are leaf executables with no background jobs. Using `exec` replaces the process entirely, cleanest approach.

##### Pattern B: Wrapper Script (non-exec)

Used in: `dispatch-unified.sh`

```bash
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

# Rest of script continues as ubuntu user...
```

**Why NOT exec?** dispatch-unified.sh spawns background jobs with `run_with_capture`. Using `exec` would break the parent process context needed for proper subprocess management.

### How It Works

1. **SSM invokes script as root** (AWS default behavior)
2. **Script checks EUID** (`$EUID -eq 0` evaluates to true for root)
3. **Script re-invokes itself via sudo -u ubuntu**:
   - `-u ubuntu`: Run as ubuntu user
   - `-E`: Preserve environment variables (GITHUB_TOKEN, etc.)
   - `HOME=/home/ubuntu`: Set HOME for credential access
4. **Re-invoked script sees EUID ≠ 0**, skips privilege drop, continues execution
5. **All subsequent operations run as ubuntu**: git, file creation, agent execution

### Benefits

- **Zero configuration**: No manual `sudo -u ubuntu` prefix needed in SSM commands
- **Backward compatible**: Old pattern with explicit `sudo -u ubuntu` still works
- **Security**: Eliminates root execution entirely
- **File ownership**: All created files are ubuntu:ubuntu (correct ownership)
- **Claude Code compatibility**: No more security refusals

### Special Considerations

#### run_with_capture Function

Original implementation used `bash -c` subshell for output capture:

```bash
# OLD - caused permission denied errors
run_with_capture() {
    local log_file="$1"
    local status_file="$2"
    shift 2
    bash -c 'set -o pipefail; "$@" 2>&1 | tee "$0"; echo ${PIPESTATUS[0]} > "$1"' "$log_file" "$status_file" "$@"
}
```

**Problem:** bash -c creates a subshell with complex file descriptor handling that caused permission denied errors when writing to status files, even after privilege drop.

**Solution:** Rewrite to run in current shell context:

```bash
# NEW - runs in current shell, no permission issues
run_with_capture() {
    local log_file="$1"
    local status_file="$2"
    shift 2
    # Run command, tee output to log, capture exit code directly
    set -o pipefail
    "$@" 2>&1 | tee "$log_file"
    local exit_code=$?
    echo "$exit_code" > "$status_file"
    return $exit_code
}
```

---

## Migration to Larger Servers

If migrating Outpost to EC2 or a larger Lightsail instance:

### SSM Agent Configuration

1. **Check SSM agent installation method**:
   ```bash
   # If installed via snap (Ubuntu 20.04+):
   systemctl list-units | grep amazon-ssm-agent
   # Look for: snap.amazon-ssm-agent.amazon-ssm-agent.service

   # If installed via package manager:
   # Look for: amazon-ssm-agent.service
   ```

2. **Create service override**:
   ```bash
   # For snap installation:
   mkdir -p /etc/systemd/system/snap.amazon-ssm-agent.amazon-ssm-agent.service.d/

   # For package installation:
   mkdir -p /etc/systemd/system/amazon-ssm-agent.service.d/

   # Create restart.conf with same content as above
   ```

3. **Apply configuration**:
   ```bash
   systemctl daemon-reload
   systemctl restart <ssm-service-name>
   systemctl show <ssm-service-name> | grep Restart=
   ```

### Dispatch Scripts

No changes needed! Privilege drop logic is portable:
- Works on any Ubuntu system
- Works with any SSM agent version
- Works with EC2, Lightsail, or on-premises hybrid activations

### Directory Structure

Ensure `/home/ubuntu/claude-executor/` directory structure:
```
/home/ubuntu/claude-executor/
├── .env                        # Environment variables
├── dispatch.sh                 # Claude Code dispatcher
├── dispatch-unified.sh         # Multi-agent dispatcher
├── dispatch-aider.sh           # Aider dispatcher
├── dispatch-codex.sh           # Codex dispatcher
├── dispatch-gemini.sh          # Gemini dispatcher
├── dispatch-grok.sh            # Grok dispatcher
├── repos/                      # Cached git repositories
└── runs/                       # Agent run workspaces
```

All files should be owned by `ubuntu:ubuntu` with execute permissions on dispatch scripts.

---

## Verification and Testing

### Test SSM Agent Status

```bash
# Check agent is running
aws ssm describe-instance-information \
  --instance-information-filter-list key=InstanceIds,valueSet=mi-0bbd8fed3f0650ddb \
  --profile soc

# Expected: PingStatus: Online
```

### Test Privilege Drop

```bash
# Invoke any dispatch script via SSM (as root)
aws ssm send-command \
  --instance-ids mi-0bbd8fed3f0650ddb \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["/home/ubuntu/claude-executor/dispatch-unified.sh blueprint \"test task\""]' \
  --profile soc

# Check output for:
# "🔒 Auto-dropping privileges from root to ubuntu user..."

# Verify no permission denied errors
```

### Test Blueprint Generation

```bash
# Full Blueprint generation test
aws ssm send-command \
  --instance-ids mi-0bbd8fed3f0650ddb \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["/home/ubuntu/claude-executor/dispatch-unified.sh blueprint \"Generate a test blueprint with 3 tasks\""]' \
  --profile soc

# Expected: Success status, no permission errors, run directory created as ubuntu:ubuntu
```

---

## Troubleshooting

### SSM Agent Not Restarting

**Symptoms:** `PingStatus: ConnectionLost` after crash

**Check:**
```bash
# Via SSM (if still accessible):
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl show snap.amazon-ssm-agent.amazon-ssm-agent.service | grep Restart=

# Via SSH:
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
```

**Fix:** Ensure restart.conf exists and systemd was reloaded.

### Permission Denied Errors Persist

**Symptoms:** Still getting "Permission denied" on temp files

**Check:**
1. Verify privilege drop message appears: `🔒 Auto-dropping privileges...`
2. Check run directory ownership:
   ```bash
   ls -la /home/ubuntu/claude-executor/runs/ | tail -5
   # Should show ubuntu:ubuntu, not root:root
   ```
3. Verify dispatch scripts have privilege drop logic:
   ```bash
   head -15 /home/ubuntu/claude-executor/dispatch-unified.sh | grep EUID
   ```

### Claude Code Still Refuses to Run

**Symptoms:** `--dangerously-skip-permissions cannot be used with root`

**Cause:** Dispatch script missing privilege drop logic or not being invoked via wrapper

**Fix:**
1. Ensure dispatch.sh has privilege drop (lines 5-9)
2. Verify it's being called via dispatch-unified.sh (not directly as root)

---

## Implementation History

| Date | Change | Commit |
|------|--------|--------|
| 2026-01-09 | SSM agent auto-restart configured (Outpost + SOC) | - |
| 2026-01-09 | Added privilege drop to all 6 dispatch scripts | 1d8df95d |
| 2026-01-09 | Fixed dispatch-unified.sh to use non-exec pattern | 1df438d8 |
| 2026-01-09 | Rewrote run_with_capture to avoid bash -c issues | bf7b7377 |

---

## References

- **Outpost SSM Instance:** mi-0bbd8fed3f0650ddb (outpost-prod, 34.195.223.189)
- **SOC SSM Instance:** mi-0d77bfe39f630bd5c (swords-of-chaos-prod)
- **AWS Profile:** soc (Account: 311493921645)
- **Scripts Location:** `/home/ubuntu/claude-executor/` on Outpost server
- **GitHub Repo:** `rgsuarez/outpost` (main branch)

---

*This configuration ensures 24/7 Outpost availability and secure, root-free agent execution.*
