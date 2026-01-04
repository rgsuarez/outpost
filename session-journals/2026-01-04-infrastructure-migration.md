# Session Journal: 2026-01-04 Outpost Infrastructure Migration

**Status:** In Progress
**Project:** Outpost
**Started:** 2026-01-04T04:27:00Z

---

## Session Objectives

1. Add OaaS to Outpost roadmap ✅
2. Analyze infrastructure options for dedicated Outpost server ✅
3. Execute migration from SOC to dedicated server 🔄

---

## Accomplishments

### 1. Fleet Consultation on OaaS ✅
- Dispatched strategic question to all 4 agents
- **Result:** 4/4 YES (with conditions)
- **Consensus:** BYOK model for MVP, context injection is the moat
- **Critical Risk:** API ToS compliance flagged by Claude Code

### 2. Infrastructure Analysis ✅
- Evaluated: Lightsail, EC2, Hetzner, DigitalOcean
- **Decision:** Lightsail medium for immediate migration
- Documented in docs/OUTPOST_INFRASTRUCTURE_ANALYSIS.md

### 3. Roadmap Created ✅
- Added MASTER_ROADMAP.md to outpost repo
- Phase 1.5: Infrastructure Migration (active)
- Phase 2.0: OaaS (planned)

### 4. Lightsail Instance Provisioned ✅
- **Instance:** outpost-prod
- **Static IP:** 34.195.223.189
- **Specs:** Ubuntu 24.04, 4GB RAM, 2 vCPU, 80GB disk
- **Cost:** $24/mo

### 5. SSM Hybrid Activation ✅
- **SSM Instance ID:** mi-0bbd8fed3f0650ddb
- **Status:** Online
- **Registration:** Successful via snap-installed agent
- **Test command:** Verified working

---

## Migration Checklist

- [x] 1. Provision Lightsail instance (outpost-prod) ✅
- [x] 2. Configure SSM hybrid activation ✅
- [ ] 3. Install dependencies (git, node, python, aws-cli) ← NEXT
- [ ] 4. Install agent CLIs (claude-code, codex, gemini, aider)
- [ ] 5. Clone dispatch scripts from repo
- [ ] 6. Configure .env with API keys
- [ ] 7. Test all 4 agents
- [ ] 8. Update SSM instance ID in docs/configs
- [ ] 9. Clean Outpost off SOC server

---

## Infrastructure Summary

| Resource | SOC (old) | outpost-prod (new) |
|----------|-----------|-------------------|
| IP | 52.44.78.2 | 34.195.223.189 |
| SSM Instance | mi-0d77bfe39f630bd5c | **mi-0bbd8fed3f0650ddb** |
| RAM | 4 GB (shared) | 4 GB (dedicated) |
| Purpose | SOC game | Outpost fleet |

---

## Commits This Session

| SHA | Message |
|-----|---------|
| `0861acc` | Add MASTER_ROADMAP.md |
| `8940def` | Add infrastructure analysis |
| `154edda` | checkpoint: Pre-provisioning state |
| `dcb4344` | checkpoint: Task 1 complete |

---

## Checkpoint 3

**Time:** 2026-01-04T08:03:00Z
**Status:** SSM operational on outpost-prod
**Next:** Task 3 - Install dependencies

**CRITICAL UPDATE FOR CONFIGS:**
```
Old SSM Instance (SOC): mi-0d77bfe39f630bd5c
New SSM Instance (Outpost): mi-0bbd8fed3f0650ddb
```

