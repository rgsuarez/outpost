# Dispatch Namespace Fix — Technical Specification

**Document Version:** 1.0.0
**Date:** 2026-01-11
**Status:** Active

---

## Executive Summary

Critical bug fix for Outpost dispatch scripts that fail when repository names are passed with GitHub namespace prefixes (e.g., `rgsuarez/awsaudit` instead of `awsaudit`). This causes path construction errors, rsync cache failures, and empty workspace errors.

**Impact:** All external integrations (MCPify, API calls) that use fully-qualified repo names currently fail.

**Solution:** Strip namespace prefix from REPO_NAME early in argument parsing while maintaining 100% backward compatibility.

---

## Current Behavior

### Problem Statement

When dispatch scripts receive repository names with namespace prefixes (format: `namespace/repo`), they construct invalid filesystem paths:

```bash
# External caller sends:
dispatch.sh "rgsuarez/awsaudit" "analyze code"

# Script constructs INVALID path:
SOURCE_REPO="/home/ubuntu/claude-executor/repos/rgsuarez/awsaudit"  # ❌ DOES NOT EXIST

# Actual repository location:
SOURCE_REPO="/home/ubuntu/claude-executor/repos/awsaudit"  # ✅ CORRECT
```

### Failure Modes

**1. Rsync Cache Miss**
```bash
# Line 74 in dispatch.sh:
SOURCE_REPO="$REPOS_DIR/$REPO_NAME"
# If REPO_NAME="rgsuarez/awsaudit", creates:
# SOURCE_REPO="/home/ubuntu/claude-executor/repos/rgsuarez/awsaudit"
# This directory doesn't exist → rsync fails → empty workspace
```

**2. Git Clone Path Error**
```bash
# Line 81 in dispatch.sh:
CLONE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
# If REPO_NAME="rgsuarez/awsaudit", creates:
# https://rgsuarez:token@github.com/rgsuarez/rgsuarez/awsaudit.git
# Double namespace → 404 error
```

### Affected Scripts

All 6 dispatch scripts exhibit this bug:

| Script | Version | REPO_NAME Assignment | SOURCE_REPO Construction | Git Clone URL |
|--------|---------|---------------------|-------------------------|---------------|
| dispatch.sh | v1.5 | Line 16, 25 | Line 74 | Line 81 |
| dispatch-codex.sh | v1.4.1 | Line 15 | Line 55 | Line 61 |
| dispatch-gemini.sh | v1.4 | Line 15 | Line 53 | Line 59 |
| dispatch-aider.sh | v1.4 | Line 15 | Line 59 | Line 65 |
| dispatch-grok.sh | v1.4 | Line 15 | Line 60 | Line 66 |
| dispatch-unified.sh | v1.1 | Line 20 | Line 245 | Line 256 |

### Evidence of Failure

From actual error logs:
```
📦 Updating cache...
📂 Creating isolated workspace...
rsync: [sender] link_stat "/home/ubuntu/claude-executor/repos/rgsuarez/awsaudit" failed: No such file or directory (2)
rsync error: some files/attrs were not transferred (see previous errors) (code 23)
🤖 Running Claude Code...
fatal: not a git repository (or any of the parent directories): .git
```

---

## Requirements

### Functional Requirements

**FR1: Namespace Stripping**
- Accept repository names in both formats:
  - Bare format: `awsaudit`, `zeOS`, `outpost`
  - Namespaced format: `rgsuarez/awsaudit`, `rgsuarez/zeOS`, `rgsuarez/outpost`
- Strip only the first slash-delimited segment if present
- Preserve the repository name portion exactly

**FR2: Backward Compatibility**
- Bare repository names MUST work unchanged
- No modification to existing call patterns
- All existing integrations continue to function

**FR3: Edge Case Handling**
- Multiple slashes: `org/namespace/repo` → `repo`
- Trailing slash: `rgsuarez/awsaudit/` → `awsaudit`
- Leading slash: `/awsaudit` → `awsaudit`
- Empty strings: Fail gracefully with existing validation
- Special characters: Handle without modification

**FR4: Implementation Constraints**
- Pure bash solution (no external commands like `cut`, `awk`, `sed`)
- Minimal performance impact
- Works in bash 4.x+ (Outpost server version)
- No subshells or command substitution in hot path

### Non-Functional Requirements

**NFR1: Performance**
- Namespace stripping adds <1ms overhead
- Uses bash parameter expansion (zero external process spawns)

**NFR2: Maintainability**
- Identical implementation across all 6 scripts
- Self-documenting code with inline comments
- Test cases included in script comments

**NFR3: Observability**
- Log namespace stripping when it occurs
- Preserve original REPO_NAME in logs for debugging
- No changes to existing log format

---

## Solution Design

### Namespace Parsing Logic

**Implementation:** Bash parameter expansion with conditional check

```bash
# After REPO_NAME assignment, before any path construction
# Strip GitHub username prefix if present (e.g., "rgsuarez/awsaudit" → "awsaudit")
if [[ "$REPO_NAME" == */* ]]; then
    ORIGINAL_REPO_NAME="$REPO_NAME"
    REPO_NAME="${REPO_NAME##*/}"
    echo "📝 Stripped namespace: $ORIGINAL_REPO_NAME → $REPO_NAME"
fi
```

**Pattern Explanation:**
- `${REPO_NAME##*/}` — Remove everything up to and including the last slash
- `[[ "$REPO_NAME" == */* ]]` — Only process if slash exists
- Conditional prevents unnecessary processing of bare names

**Test Cases:**

| Input | Output | Explanation |
|-------|--------|-------------|
| `awsaudit` | `awsaudit` | No slash → unchanged |
| `rgsuarez/awsaudit` | `awsaudit` | Single namespace → stripped |
| `org/rgsuarez/awsaudit` | `awsaudit` | Multiple namespaces → all stripped |
| `awsaudit/` | `awsaudit` | Trailing slash → handled |
| `/awsaudit` | `awsaudit` | Leading slash → handled |
| `aws-audit-2024` | `aws-audit-2024` | No slash → unchanged |
| `rgsuarez/aws.audit` | `aws.audit` | Special chars preserved |

### Integration Points

**1. dispatch.sh (v1.5 → v1.6)**
- Insert after line 27 (after argument parsing)
- Before line 74 (SOURCE_REPO construction)

**2. dispatch-codex.sh (v1.4.1 → v1.5)**
- Insert after line 15 (after REPO_NAME assignment)
- Before line 55 (SOURCE_REPO construction)

**3. dispatch-gemini.sh, dispatch-aider.sh, dispatch-grok.sh (v1.4 → v1.5)**
- Insert after line 15 (after REPO_NAME assignment)
- Before SOURCE_REPO construction (lines 53, 59, 60 respectively)

**4. dispatch-unified.sh (v1.1 → v1.2)**
- Insert after line 20 (after REPO_NAME assignment)
- Before line 245 (SOURCE_REPO construction in cache warming)

### Rollback Strategy

**Pre-deployment:**
- All scripts versioned in git
- AWS SSM backup created with timestamp

**Rollback procedure:**
```bash
# Server-side rollback
cd /home/ubuntu/claude-executor
git reset --hard <previous-commit-sha>

# Or restore from backup
cp -a /home/ubuntu/backups/scripts-YYYYMMDD-HHMMSS/* /home/ubuntu/claude-executor/scripts/
```

---

## Testing Strategy

### Unit Tests

**Test Suite:** `tests/unit/test_namespace_parsing.sh`

Test functions:
1. `test_with_namespace()` — Verify `rgsuarez/awsaudit` → `awsaudit`
2. `test_without_namespace()` — Verify `awsaudit` → `awsaudit` (unchanged)
3. `test_edge_cases()` — Verify multiple slashes, trailing slashes, etc.

### Integration Tests

**Test Suite:** `tests/integration/test_dispatch_namespace.sh`

Test scenarios:
1. Each agent script invoked with namespaced repo name
2. Verify correct path construction
3. Verify workspace creation succeeds
4. No regression in bare name handling

### Production Smoke Test

**Approach:** Deploy single script to Outpost, test with real query

1. Deploy `dispatch-codex.sh` only
2. Execute test query: `dispatch-codex.sh "rgsuarez/awsaudit" "list files"`
3. Verify workspace created, no rsync errors
4. Rollback test deployment
5. Proceed with full deployment if successful

---

## Deployment Plan

### Phase 1: Local Testing (T2.1, T2.2)
- Run unit tests on all 6 scripts
- Run integration tests locally
- Verify all tests pass

### Phase 2: Production Smoke Test (T2.3)
- Deploy dispatch-codex.sh to Outpost
- Execute single test query with namespaced repo
- Verify success, rollback

### Phase 3: Full Deployment (T3.1)
1. Create backup of current production scripts
2. Git commit all changes
3. Push to GitHub main branch
4. AWS SSM command to pull latest on server
5. Verify deployment

### Phase 4: Production Validation (T4)
1. Execute awsaudit test query with namespace format
2. Verify cache behavior
3. Test all 5 agents with namespaced repos
4. Generate validation report

---

## Success Metrics

| Metric | Target | Validation Method |
|--------|--------|------------------|
| Namespace format acceptance | 100% | All scripts handle both formats |
| Backward compatibility | 100% | Existing bare names still work |
| Empty workspace failures | 0 | No rsync cache miss errors |
| Test coverage | 100% | Both formats tested per script |
| Deployment success | 100% | All scripts deployed without errors |
| Production validation | 100% | Real query succeeds with namespaced repo |

---

## Appendix A: Bash Pattern Reference

**Parameter Expansion Patterns:**

```bash
${variable##pattern}   # Remove longest match from beginning
${variable#pattern}    # Remove shortest match from beginning
${variable%%pattern}   # Remove longest match from end
${variable%pattern}    # Remove shortest match from end
```

**Our choice:** `${REPO_NAME##*/}` removes everything up to and including the last `/`

**Alternative considered:** `${REPO_NAME#*/}` (shortest match)
- Problem: `org/namespace/repo` → `namespace/repo` (doesn't strip all namespaces)
- Solution: Use `##*/` to strip ALL namespaces, leaving only the repo name

---

## Appendix B: Version Bump Matrix

| Script | Current Version | New Version | Change Description |
|--------|----------------|-------------|-------------------|
| dispatch.sh | v1.5 | v1.6 | Add namespace stripping |
| dispatch-codex.sh | v1.4.1 | v1.5 | Add namespace stripping |
| dispatch-gemini.sh | v1.4 | v1.5 | Add namespace stripping |
| dispatch-aider.sh | v1.4 | v1.5 | Add namespace stripping |
| dispatch-grok.sh | v1.4 | v1.5 | Add namespace stripping |
| dispatch-unified.sh | v1.1 | v1.2 | Add namespace stripping |

---

**Document Control:**
- Author: Claude Sonnet 4.5
- Reviewed: Pending
- Approved: Pending
