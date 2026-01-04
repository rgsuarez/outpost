# Outpost Infrastructure Analysis

**Date:** 2026-01-04
**Purpose:** Migrate Outpost off SOC server to dedicated infrastructure
**Decision Required:** Server provider, instance size, architecture

---

## Current State (SOC Shared Server)

| Resource | SOC Server | Outpost Usage |
|----------|------------|---------------|
| Instance | Lightsail medium_3_0 | Shared |
| RAM | 4 GB | ~500MB idle |
| CPU | 2 cores | I/O bound (API calls) |
| Disk | 80 GB | 3.1 GB (runs: 2.8GB, cache: 364MB) |
| Cost | $24/mo | $0 (shared) |
| SSM | mi-0d77bfe39f630bd5c | Active |

**Problem:** SOC game + Outpost on same server causes conflicts. Need isolation.

---

## Requirements for Dedicated Outpost Server

### Minimum Viable
- Run 4 AI CLIs concurrently (Claude Code, Codex, Gemini, Aider)
- Handle 2-4 simultaneous user requests
- Workspace isolation per task
- SSM agent for remote dispatch
- Git operations (clone, checkout, diff)
- Stable public IP (or SSM hybrid activation)

### Future Growth (OaaS)
- Handle 10-20 concurrent users
- 40+ simultaneous agent processes
- Horizontal scaling capability
- Load balancing

### Resource Estimates

| Scenario | Concurrent Tasks | RAM Needed | Disk Needed | CPU |
|----------|------------------|------------|-------------|-----|
| Single user, 4 agents | 4 | 2 GB | 10 GB | 2 |
| 4 users, 4 agents each | 16 | 4-6 GB | 40 GB | 2-4 |
| 10 users, 4 agents each | 40 | 8-12 GB | 100 GB | 4-8 |

**Note:** AI CLI tools are I/O bound (waiting on API responses). CPU is rarely the bottleneck.

---

## Option 1: AWS Lightsail (Recommended for MVP)

**Pros:**
- Predictable pricing (no surprise bills)
- Simple management
- SSM hybrid activation works
- Same ecosystem as current infra
- Static IP included

**Cons:**
- Less flexible than EC2
- No spot pricing
- Fixed instance sizes

### Recommended Tier: `large_3_0`

| Spec | Value |
|------|-------|
| RAM | 8 GB |
| CPU | 2 cores |
| Disk | 160 GB |
| Transfer | 5 TB |
| **Cost** | **$44/mo** |

**Why not medium ($24)?** 4GB RAM is tight for concurrent workloads. 8GB gives headroom.

**Cost Mitigation:** Start with medium ($24), monitor usage, upgrade if needed. Lightsail allows in-place upgrades.

---

## Option 2: AWS EC2

**Pros:**
- More instance types
- Spot instances (60-90% savings)
- Reserved instances (40% savings)
- More control

**Cons:**
- Separate EBS charges
- Data transfer charges
- More complex billing
- Spot can be interrupted

### On-Demand Pricing

| Instance | vCPU | RAM | Cost/mo |
|----------|------|-----|---------|
| t3.medium | 2 | 4 GB | ~$30 |
| t3.large | 2 | 8 GB | ~$60 |
| t3.xlarge | 4 | 16 GB | ~$120 |
| m6i.large | 2 | 8 GB | ~$70 |

+ EBS: ~$8/mo for 100GB gp3
+ Data transfer: Variable

**Spot Instance Potential:** t3.large spot = ~$15-20/mo (but can be interrupted)

---

## Option 3: Hetzner Cloud (Budget Option)

**Pros:**
- 50-70% cheaper than AWS
- Predictable pricing
- Good specs for price
- European + US regions

**Cons:**
- No SSM (need alternative remote access)
- Different ecosystem
- Less integration with existing AWS infra
- Latency to AWS services (if any)

### Pricing

| Server | vCPU | RAM | Disk | Cost/mo |
|--------|------|-----|------|---------|
| CPX21 | 3 | 4 GB | 80 GB | $8.50 |
| CPX31 | 4 | 8 GB | 160 GB | $15 |
| CPX41 | 8 | 16 GB | 240 GB | $28 |
| CPX51 | 16 | 32 GB | 360 GB | $65 |

**CPX31 at $15/mo** gives 8GB RAM, 4 vCPU, 160GB disk — comparable to Lightsail large at $44.

**SSM Alternative:** Use Tailscale or WireGuard VPN for remote access.

---

## Option 4: DigitalOcean

**Pros:**
- Simple, predictable
- Good developer experience
- Managed Kubernetes available

**Cons:**
- No SSM
- Slightly more expensive than Hetzner

### Pricing

| Droplet | vCPU | RAM | Disk | Cost/mo |
|---------|------|-----|------|---------|
| Basic 4GB | 2 | 4 GB | 80 GB | $24 |
| Basic 8GB | 4 | 8 GB | 160 GB | $48 |

Similar to Lightsail pricing.

---

## Cost Comparison Summary

| Provider | 8GB RAM Config | Monthly Cost | Notes |
|----------|----------------|--------------|-------|
| **Hetzner CPX31** | 4 vCPU, 160GB | **$15** | Cheapest, no SSM |
| Lightsail large | 2 vCPU, 160GB | $44 | Simple, SSM works |
| DigitalOcean 8GB | 4 vCPU, 160GB | $48 | No SSM |
| EC2 t3.large | 2 vCPU, 8GB+EBS | ~$70 | Complex billing |
| EC2 t3.large spot | 2 vCPU, 8GB+EBS | ~$20-25 | Interruptible |

---

## SSM vs Alternative Remote Access

### If we use SSM (AWS Lightsail/EC2):
- Existing dispatch scripts work unchanged
- `aws ssm send-command` pattern continues
- Hybrid activation for Lightsail
- **No code changes needed**

### If we drop SSM (Hetzner/DO):
- Need new dispatch mechanism
- Options:
  1. **SSH-based dispatch**: `ssh outpost@server "dispatch.sh ..."`
  2. **HTTP API on server**: FastAPI listening on port, dispatch via POST
  3. **Message queue**: SQS/Redis queue, server polls for tasks
- **Moderate code changes** (but aligns with OaaS anyway)

**Recommendation:** If building OaaS soon, HTTP API is the right path regardless. SSM was a shortcut for operator-only access.

---

## Architecture Decision

### Path A: Stay AWS, Keep SSM (Conservative)
- Lightsail large ($44/mo)
- SSM hybrid activation
- Minimal code changes
- Migrate in 1-2 hours

### Path B: Hetzner + HTTP API (Cost-Optimized + OaaS-Ready)
- Hetzner CPX31 ($15/mo)
- Build lightweight HTTP dispatcher
- Tailscale for operator SSH access
- Saves $30/mo, positions for OaaS
- 1-2 days to implement

### Path C: AWS + HTTP API (Balanced)
- Lightsail large ($44/mo)
- Build HTTP API anyway (for OaaS)
- Keep SSM as backup
- Best of both worlds

---

## Recommendation

**For immediate migration (this week):** Path A — Lightsail large ($44/mo)
- Fastest path to unblocking SOC conflicts
- Zero code changes to dispatch scripts
- Upgrade path clear

**For OaaS build (next month):** Transition to Path B or C
- Build HTTP API layer as part of OaaS
- Evaluate Hetzner migration once API is proven
- $30/mo savings compounds

---

## Cost Projection

| Scenario | Monthly | Annual |
|----------|---------|--------|
| Current (shared with SOC) | $0 | $0 |
| Lightsail large (dedicated) | $44 | $528 |
| Hetzner CPX31 (dedicated) | $15 | $180 |
| Fleet subscriptions | $170 | $2,040 |

**Total Outpost infrastructure (Lightsail):** $214/mo
**Total Outpost infrastructure (Hetzner):** $185/mo

---

## Immediate Action Items

1. [ ] **Provision Lightsail large instance** (outpost-prod)
2. [ ] **Configure SSM hybrid activation**
3. [ ] **Clone Outpost setup** (dispatch scripts, .env, agent CLIs)
4. [ ] **Update SSM instance ID** in zeOS/preferences
5. [ ] **Test all 4 agents** on new server
6. [ ] **Update OUTPOST_INTERFACE.md** with new instance ID
7. [ ] **Decommission Outpost from SOC** (remove scripts, clean disk)

---

## Future: OaaS Infrastructure

When ready for multi-tenant OaaS:

```
┌─────────────────────────────────────────────────────────────┐
│                    API Gateway (Lambda)                     │
│                    api.outpost.dev                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    SQS Task Queue                           │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │ Worker 1│   │ Worker 2│   │ Worker N│  (Auto-scaling)
   │ Outpost │   │ Outpost │   │ Outpost │
   └─────────┘   └─────────┘   └─────────┘
```

But that's Phase 2. For now: single dedicated server.
