# Outpost Dispatch Namespace Fix — Implementation Blueprint

> **Document Status**: Active
> **Last Updated**: 2026-01-11
> **Owner**: Platform Team

<!-- BLUEPRINT METADATA (DO NOT REMOVE) -->
<!-- _blueprint_version: 2.0.1 -->
<!-- _generated_at: 2026-01-11T23:30:00Z -->
<!-- _generator: claude-sonnet-4-5 (manual) -->
<!-- _depth: 3 -->
<!-- _tiers_generated: T0, T1, T2, T3, T4 -->
<!-- END METADATA -->

---

## Strategic Vision

Fix critical dispatch script failure caused by namespaced repository names (`rgsuarez/awsaudit`) being passed when scripts expect bare names (`awsaudit`). This causes rsync cache failures, resulting in empty workspaces and failed agent executions.

**Current Behavior:**
```bash
# MCPify or external callers send:
dispatch.sh "rgsuarez/awsaudit" "analyze code"

# Script constructs invalid path:
SOURCE_REPO="/home/ubuntu/claude-executor/repos/rgsuarez/awsaudit"  # ❌ Doesn't exist

# Actual repo location:
SOURCE_REPO="/home/ubuntu/claude-executor/repos/awsaudit"  # ✅ Correct
```

**Target State:**
All dispatch scripts accept both formats:
- `dispatch.sh awsaudit "task"` → Works (existing)
- `dispatch.sh rgsuarez/awsaudit "task"` → Works (new capability)

**Scope:** 6 dispatch scripts (dispatch.sh, dispatch-codex.sh, dispatch-gemini.sh, dispatch-aider.sh, dispatch-grok.sh, dispatch-unified.sh)

---

## Success Metrics

| Metric | Target | Validation |
|--------|--------|------------|
| Namespace format acceptance | 100% | All scripts handle both formats |
| Backward compatibility | 100% | Existing bare names still work |
| Empty workspace failures | 0 | No rsync cache miss errors |
| Test coverage | 100% | Both formats tested per script |
| Deployment success | 100% | All scripts deployed without errors |
| Production validation | 100% | Real query succeeds with namespaced repo |

---

## Execution Configuration

```yaml
execution:
  shell: bash
  shell_flags: ["-e", "-o", "pipefail"]
  max_parallel_tasks: 3

  resource_locks:
    - name: "outpost_scripts"
      type: exclusive

  preflight_checks:
    - command: "aws --version"
      expected_exit_code: 0
      error_message: "AWS CLI v2 required"
    - command: "test -f ~/.aws/credentials"
      expected_exit_code: 0
      error_message: "AWS credentials not configured"
    - command: "git diff --quiet scripts/"
      expected_exit_code: 0
      error_message: "Uncommitted changes in scripts/ directory"

  secret_resolution:
    on_missing: abort
    sources:
      - type: env
        prefix: ""
      - type: file
        path: ".env"
```

---

## Tier 0: Foundation — Analysis & Design

### T0.1: Root Cause Analysis & Specification

```yaml
task_id: T0.1
name: "Document root cause and define fix requirements"
status: not_started
dependencies: []

interface:
  input: "Error logs from failed awsaudit dispatch, current dispatch scripts"
  output: "docs/DISPATCH_NAMESPACE_FIX_SPEC.md with problem statement and solution design"

acceptance_criteria:
  - Root cause clearly documented with evidence
  - Both failure modes identified (rsync path, git clone path)
  - Backward compatibility requirements specified
  - Edge cases enumerated (multiple slashes, no namespace, etc.)
  - Solution design reviewed and approved

verification:
  smoke:
    command: "test -f docs/DISPATCH_NAMESPACE_FIX_SPEC.md && grep -q 'namespace stripping' docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
    expected_exit_code: 0

rollback: "git restore docs/DISPATCH_NAMESPACE_FIX_SPEC.md"

output:
  location: file
  path: "docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
  ports:
    spec:
      type: markdown

required_capabilities:
  - git
  - bash
```

#### T0.1.1: Document Current Behavior

```yaml
task_id: T0.1.1
name: "Document how dispatch scripts currently parse REPO_NAME"
status: not_started
dependencies: []

interface:
  input: "All 6 dispatch scripts (dispatch.sh, dispatch-codex.sh, etc.)"
  output: "Section in spec doc showing current REPO_NAME handling"

acceptance_criteria:
  - All 6 scripts analyzed for REPO_NAME usage
  - Path construction logic documented (REPOS_DIR + REPO_NAME)
  - Cache behavior documented (git clone, rsync)
  - Evidence of failure with namespaced names captured

verification:
  smoke:
    command: "grep -q 'Current Behavior' docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
    expected_exit_code: 0

rollback: "git restore docs/DISPATCH_NAMESPACE_FIX_SPEC.md"

output:
  location: file
  path: "docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
  ports:
    analysis:
      type: markdown

required_capabilities:
  - bash
  - grep
```

#### T0.1.2: Define Fix Requirements

```yaml
task_id: T0.1.2
name: "Specify requirements for namespace stripping implementation"
status: not_started
dependencies: [T0.1.1]

interface:
  input: "Current behavior analysis from T0.1.1"
  output: "Requirements section in spec doc"

acceptance_criteria:
  - Accept both 'repo' and 'namespace/repo' formats
  - Strip only the first slash-delimited segment if present
  - Preserve backward compatibility (bare names unchanged)
  - Handle edge cases (multiple slashes, trailing slashes, empty strings)
  - Implementation must be pure bash (no external dependencies)

verification:
  smoke:
    command: "grep -q 'Requirements' docs/DISPATCH_NAMESPACE_FIX_SPEC.md && grep -q 'backward compatibility' docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
    expected_exit_code: 0

rollback: "git restore docs/DISPATCH_NAMESPACE_FIX_SPEC.md"

output:
  location: file
  path: "docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
  ports:
    requirements:
      type: markdown

required_capabilities:
  - bash
```

#### T0.1.3: Design Namespace Parsing Logic

```yaml
task_id: T0.1.3
name: "Design bash pattern for namespace extraction"
status: not_started
dependencies: [T0.1.2]

interface:
  input: "Requirements from T0.1.2"
  output: "Bash code snippet in spec doc with test cases"

acceptance_criteria:
  - Bash parameter expansion pattern defined
  - Test cases cover all edge cases
  - Performance impact minimal (no subshells/external commands)
  - Pattern works in bash 4.x+ (Outpost server version)
  - Code snippet is copy-paste ready

verification:
  smoke:
    command: "grep -q 'REPO_NAME.*##.*/' docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
    expected_exit_code: 0

rollback: "git restore docs/DISPATCH_NAMESPACE_FIX_SPEC.md"

output:
  location: file
  path: "docs/DISPATCH_NAMESPACE_FIX_SPEC.md"
  ports:
    pattern:
      type: bash_snippet

required_capabilities:
  - bash
```

---

## Tier 1: Implementation — Dispatch Script Updates

### T1.1: Update dispatch.sh

```yaml
task_id: T1.1
name: "Add namespace stripping to dispatch.sh"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Bash pattern from T0.1.3, current dispatch.sh"
  output: "Updated dispatch.sh with namespace handling"

acceptance_criteria:
  - Namespace stripping logic added after argument parsing
  - Version bumped to v1.6
  - Logging added to show stripped namespace
  - Backward compatibility preserved
  - No other functional changes

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch.sh && grep -q 'v1.6' scripts/dispatch.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch.sh"
    expected_exit_code: 0
    timeout: PT10S

rollback: "git restore scripts/dispatch.sh"

output:
  location: file
  path: "scripts/dispatch.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
  - git
```

#### T1.1.1: Add Namespace Stripping Logic

```yaml
task_id: T1.1.1
name: "Insert namespace parsing code in dispatch.sh"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Bash pattern from T0.1.3"
  output: "dispatch.sh with namespace stripping added after line 26"

acceptance_criteria:
  - Code inserted after argument parsing, before REPO_NAME validation
  - Uses bash parameter expansion (${REPO_NAME##*/})
  - Conditional check (if contains /)
  - Debug logging added
  - Syntax validated with bash -n

verification:
  smoke:
    command: "sed -n '27,35p' scripts/dispatch.sh | grep -q 'REPO_NAME##'"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch.sh"

output:
  location: file
  path: "scripts/dispatch.sh"
  ports:
    updated_script:
      type: bash

required_capabilities:
  - bash
  - sed
```

#### T1.1.2: Add Backwards Compatibility Tests

```yaml
task_id: T1.1.2
name: "Create inline test cases in dispatch.sh comments"
status: not_started
dependencies: [T1.1.1]

interface:
  input: "Updated dispatch.sh from T1.1.1"
  output: "Test cases documented in comments"

acceptance_criteria:
  - Comment block with test cases added
  - Examples show both formats working
  - Edge cases documented
  - Tests are executable (can be extracted and run)

verification:
  smoke:
    command: "grep -q 'Test cases:' scripts/dispatch.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch.sh"

output:
  location: file
  path: "scripts/dispatch.sh"
  ports:
    documented_script:
      type: bash

required_capabilities:
  - bash
```

#### T1.1.3: Update Version Number

```yaml
task_id: T1.1.3
name: "Bump dispatch.sh version to v1.6"
status: not_started
dependencies: [T1.1.2]

interface:
  input: "Updated dispatch.sh from T1.1.2"
  output: "dispatch.sh with version v1.6"

acceptance_criteria:
  - Version comment updated to v1.6
  - Changelog comment added describing namespace fix
  - No other changes to script

verification:
  smoke:
    command: "grep -q 'v1.6' scripts/dispatch.sh && grep -q 'namespace' scripts/dispatch.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch.sh"

output:
  location: file
  path: "scripts/dispatch.sh"
  ports:
    versioned_script:
      type: bash

required_capabilities:
  - bash
```

### T1.2: Update dispatch-codex.sh

```yaml
task_id: T1.2
name: "Add namespace stripping to dispatch-codex.sh"
status: not_started
dependencies: [T1.1]

interface:
  input: "Pattern from dispatch.sh, current dispatch-codex.sh"
  output: "Updated dispatch-codex.sh with namespace handling"

acceptance_criteria:
  - Same namespace logic as dispatch.sh
  - Version bumped to v1.5
  - Syntax validated
  - Backward compatibility preserved

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch-codex.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch-codex.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-codex.sh"

output:
  location: file
  path: "scripts/dispatch-codex.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
```

#### T1.2.1: Add Namespace Stripping Logic

```yaml
task_id: T1.2.1
name: "Insert namespace parsing code in dispatch-codex.sh"
status: not_started
dependencies: [T1.1.1]

interface:
  input: "Tested pattern from T1.1.1"
  output: "dispatch-codex.sh with namespace stripping"

acceptance_criteria:
  - Code inserted after REPO_NAME assignment (after line 24)
  - Identical logic to dispatch.sh
  - Debug logging matches dispatch.sh format
  - Syntax validated

verification:
  smoke:
    command: "grep -q 'REPO_NAME##' scripts/dispatch-codex.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-codex.sh"

output:
  location: file
  path: "scripts/dispatch-codex.sh"
  ports:
    updated_script:
      type: bash

required_capabilities:
  - bash
```

#### T1.2.2: Update Version Number

```yaml
task_id: T1.2.2
name: "Bump dispatch-codex.sh version to v1.5"
status: not_started
dependencies: [T1.2.1]

interface:
  input: "Updated dispatch-codex.sh from T1.2.1"
  output: "dispatch-codex.sh with version v1.5"

acceptance_criteria:
  - Version comment updated to v1.5
  - Changelog added
  - Consistent with dispatch.sh format

verification:
  smoke:
    command: "grep -q 'v1.5' scripts/dispatch-codex.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-codex.sh"

output:
  location: file
  path: "scripts/dispatch-codex.sh"
  ports:
    versioned_script:
      type: bash

required_capabilities:
  - bash
```

### T1.3: Update dispatch-gemini.sh

```yaml
task_id: T1.3
name: "Add namespace stripping to dispatch-gemini.sh"
status: not_started
dependencies: [T1.1]

interface:
  input: "Pattern from dispatch.sh, current dispatch-gemini.sh"
  output: "Updated dispatch-gemini.sh with namespace handling"

acceptance_criteria:
  - Same namespace logic as dispatch.sh
  - Version bumped appropriately
  - Syntax validated
  - Backward compatibility preserved

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch-gemini.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch-gemini.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-gemini.sh"

output:
  location: file
  path: "scripts/dispatch-gemini.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
```

### T1.4: Update dispatch-aider.sh

```yaml
task_id: T1.4
name: "Add namespace stripping to dispatch-aider.sh"
status: not_started
dependencies: [T1.1]

interface:
  input: "Pattern from dispatch.sh, current dispatch-aider.sh"
  output: "Updated dispatch-aider.sh with namespace handling"

acceptance_criteria:
  - Same namespace logic as dispatch.sh
  - Version bumped appropriately
  - Syntax validated
  - Backward compatibility preserved

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch-aider.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch-aider.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-aider.sh"

output:
  location: file
  path: "scripts/dispatch-aider.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
```

### T1.5: Update dispatch-grok.sh

```yaml
task_id: T1.5
name: "Add namespace stripping to dispatch-grok.sh"
status: not_started
dependencies: [T1.1]

interface:
  input: "Pattern from dispatch.sh, current dispatch-grok.sh"
  output: "Updated dispatch-grok.sh with namespace handling"

acceptance_criteria:
  - Same namespace logic as dispatch.sh
  - Version bumped appropriately
  - Syntax validated
  - Backward compatibility preserved

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch-grok.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch-grok.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-grok.sh"

output:
  location: file
  path: "scripts/dispatch-grok.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
```

### T1.6: Update dispatch-unified.sh

```yaml
task_id: T1.6
name: "Add namespace stripping to dispatch-unified.sh"
status: not_started
dependencies: [T1.1]

interface:
  input: "Pattern from dispatch.sh, current dispatch-unified.sh"
  output: "Updated dispatch-unified.sh with namespace handling"

acceptance_criteria:
  - Same namespace logic as dispatch.sh
  - Placed in cache warming function if applicable
  - Version bumped appropriately
  - Syntax validated
  - Backward compatibility preserved

verification:
  smoke:
    command: "grep -q 'Strip GitHub username prefix' scripts/dispatch-unified.sh || grep -q 'REPO_NAME##' scripts/dispatch-unified.sh"
    expected_exit_code: 0
  unit:
    command: "bash -n scripts/dispatch-unified.sh"
    expected_exit_code: 0

rollback: "git restore scripts/dispatch-unified.sh"

output:
  location: file
  path: "scripts/dispatch-unified.sh"
  ports:
    script:
      type: bash

required_capabilities:
  - bash
```

---

## Tier 2: Testing — Validation & Verification

### T2.1: Unit Tests for Namespace Parsing

```yaml
task_id: T2.1
name: "Create unit test suite for namespace parsing logic"
status: not_started
dependencies: [T1.1, T1.2, T1.3, T1.4, T1.5, T1.6]

interface:
  input: "All updated dispatch scripts"
  output: "tests/unit/test_namespace_parsing.sh"

acceptance_criteria:
  - Tests cover both formats (with/without namespace)
  - Edge cases tested (multiple slashes, empty, special chars)
  - All 6 dispatch scripts tested
  - Tests run in isolation (no external dependencies)
  - Test suite exits 0 on success

verification:
  smoke:
    command: "test -f tests/unit/test_namespace_parsing.sh && bash -n tests/unit/test_namespace_parsing.sh"
    expected_exit_code: 0
  unit:
    command: "bash tests/unit/test_namespace_parsing.sh"
    expected_exit_code: 0
    timeout: PT30S

rollback: "git restore tests/unit/test_namespace_parsing.sh"

output:
  location: file
  path: "tests/unit/test_namespace_parsing.sh"
  ports:
    test_suite:
      type: bash

required_capabilities:
  - bash
```

#### T2.1.1: Test With Namespace Prefix

```yaml
task_id: T2.1.1
name: "Test namespace format rgsuarez/repo"
status: not_started
dependencies: [T1.1]

interface:
  input: "Updated dispatch scripts"
  output: "Test case function in test suite"

acceptance_criteria:
  - Test case validates 'rgsuarez/awsaudit' → 'awsaudit'
  - Test case validates 'rgsuarez/zeOS' → 'zeOS'
  - Assertions verify correct stripping
  - Test is idempotent

verification:
  smoke:
    command: "grep -q 'test_with_namespace' tests/unit/test_namespace_parsing.sh"
    expected_exit_code: 0

rollback: "git restore tests/unit/test_namespace_parsing.sh"

output:
  location: file
  path: "tests/unit/test_namespace_parsing.sh"
  ports:
    test_function:
      type: bash

required_capabilities:
  - bash
```

#### T2.1.2: Test Without Namespace Prefix

```yaml
task_id: T2.1.2
name: "Test bare format (backward compatibility)"
status: not_started
dependencies: [T1.1]

interface:
  input: "Updated dispatch scripts"
  output: "Test case function in test suite"

acceptance_criteria:
  - Test case validates 'awsaudit' → 'awsaudit' (unchanged)
  - Test case validates 'zeOS' → 'zeOS' (unchanged)
  - Assertions verify no modification
  - Test is idempotent

verification:
  smoke:
    command: "grep -q 'test_without_namespace' tests/unit/test_namespace_parsing.sh"
    expected_exit_code: 0

rollback: "git restore tests/unit/test_namespace_parsing.sh"

output:
  location: file
  path: "tests/unit/test_namespace_parsing.sh"
  ports:
    test_function:
      type: bash

required_capabilities:
  - bash
```

#### T2.1.3: Test Edge Cases

```yaml
task_id: T2.1.3
name: "Test edge cases (multiple slashes, empty, etc.)"
status: not_started
dependencies: [T1.1]

interface:
  input: "Updated dispatch scripts"
  output: "Test case function in test suite"

acceptance_criteria:
  - Test 'org/namespace/repo' → 'repo' (multiple slashes)
  - Test 'repo/' → 'repo' (trailing slash)
  - Test '/repo' → 'repo' (leading slash)
  - Test empty string handling
  - Assertions verify correct behavior

verification:
  smoke:
    command: "grep -q 'test_edge_cases' tests/unit/test_namespace_parsing.sh"
    expected_exit_code: 0

rollback: "git restore tests/unit/test_namespace_parsing.sh"

output:
  location: file
  path: "tests/unit/test_namespace_parsing.sh"
  ports:
    test_function:
      type: bash

required_capabilities:
  - bash
```

### T2.2: Integration Tests

```yaml
task_id: T2.2
name: "Create integration test suite using local test mode"
status: not_started
dependencies: [T2.1]

interface:
  input: "All updated dispatch scripts, unit test results"
  output: "tests/integration/test_dispatch_namespace.sh"

acceptance_criteria:
  - Tests run dispatch scripts in dry-run/test mode
  - Both namespace formats tested end-to-end
  - Tests verify cache path construction
  - Tests verify workspace creation
  - No actual API calls or agent execution

verification:
  smoke:
    command: "test -f tests/integration/test_dispatch_namespace.sh"
    expected_exit_code: 0
  integration:
    command: "bash tests/integration/test_dispatch_namespace.sh"
    expected_exit_code: 0
    timeout: PT2M

rollback: "git restore tests/integration/test_dispatch_namespace.sh"

output:
  location: file
  path: "tests/integration/test_dispatch_namespace.sh"
  ports:
    test_suite:
      type: bash

required_capabilities:
  - bash
  - git
```

#### T2.2.1: Test Each Agent Individually

```yaml
task_id: T2.2.1
name: "Test all 5 agent dispatch scripts with namespaced repos"
status: not_started
dependencies: [T2.1]

interface:
  input: "Updated dispatch scripts"
  output: "Individual agent test cases in integration suite"

acceptance_criteria:
  - Test dispatch.sh (Claude)
  - Test dispatch-codex.sh
  - Test dispatch-gemini.sh
  - Test dispatch-aider.sh
  - Test dispatch-grok.sh
  - Each test validates correct path construction

verification:
  smoke:
    command: "grep -c 'test_.*_dispatch' tests/integration/test_dispatch_namespace.sh | grep -q '^5$'"
    expected_exit_code: 0

rollback: "git restore tests/integration/test_dispatch_namespace.sh"

output:
  location: file
  path: "tests/integration/test_dispatch_namespace.sh"
  ports:
    agent_tests:
      type: bash

required_capabilities:
  - bash
```

#### T2.2.2: Test Unified Dispatch

```yaml
task_id: T2.2.2
name: "Test dispatch-unified.sh with namespaced repos"
status: not_started
dependencies: [T2.1]

interface:
  input: "Updated dispatch-unified.sh"
  output: "Unified dispatch test case in integration suite"

acceptance_criteria:
  - Test single executor mode
  - Test multi-executor mode (all)
  - Verify namespace stripped before agent dispatch
  - Verify cache warming handles both formats

verification:
  smoke:
    command: "grep -q 'test_unified_dispatch' tests/integration/test_dispatch_namespace.sh"
    expected_exit_code: 0

rollback: "git restore tests/integration/test_dispatch_namespace.sh"

output:
  location: file
  path: "tests/integration/test_dispatch_namespace.sh"
  ports:
    unified_test:
      type: bash

required_capabilities:
  - bash
```

### T2.3: Production Smoke Test

```yaml
task_id: T2.3
name: "Run smoke test on Outpost server before full deployment"
status: not_started
dependencies: [T2.2]

interface:
  input: "Integration test results, AWS SSM access"
  output: "Smoke test results in test log"

acceptance_criteria:
  - Deploy ONE script (dispatch-codex.sh) to test server
  - Run simple test query with namespaced repo
  - Verify workspace created correctly
  - Verify no errors in output
  - Rollback test deployment after validation

verification:
  smoke:
    command: "test -f tests/smoke/outpost_namespace_test.log && grep -q 'SUCCESS' tests/smoke/outpost_namespace_test.log"
    expected_exit_code: 0

rollback: "aws ssm send-command --instance-ids mi-0bbd8fed3f0650ddb --document-name AWS-RunShellScript --parameters 'commands=[\"git -C /home/ubuntu/claude-executor/repos/outpost checkout scripts/dispatch-codex.sh\"]' --profile soc"

output:
  location: file
  path: "tests/smoke/outpost_namespace_test.log"
  ports:
    smoke_results:
      type: text

required_capabilities:
  - bash
  - aws-cli
```

---

## Tier 3: Deployment — Push to Production

### T3.1: Deploy to Outpost Server

```yaml
task_id: T3.1
name: "Deploy all updated dispatch scripts to production server"
status: not_started
dependencies: [T2.3]

interface:
  input: "Tested dispatch scripts, AWS SSM access"
  output: "Deployment confirmation log"

acceptance_criteria:
  - All 6 scripts deployed successfully
  - Permissions preserved (executable)
  - Server-side git pull or file sync completed
  - Deployment logged with timestamps
  - No service disruption during deployment

verification:
  smoke:
    command: "grep -q 'Deployment completed' logs/deployment_$(date +%Y%m%d).log"
    expected_exit_code: 0

rollback: "aws ssm send-command --instance-ids mi-0bbd8fed3f0650ddb --document-name AWS-RunShellScript --parameters 'commands=[\"cd /home/ubuntu/claude-executor && git reset --hard HEAD~1\"]' --profile soc"

output:
  location: file
  path: "logs/deployment_$(date +%Y%m%d).log"
  ports:
    deployment_log:
      type: text

required_capabilities:
  - bash
  - aws-cli
  - git
```

#### T3.1.1: Backup Current Scripts

```yaml
task_id: T3.1.1
name: "Create backup of current production scripts"
status: not_started
dependencies: [T2.3]

interface:
  input: "AWS SSM access to Outpost server"
  output: "Backup created on server"

acceptance_criteria:
  - Backup directory created with timestamp
  - All 6 current scripts copied to backup
  - Backup verified (file count, checksums)
  - Backup path logged

verification:
  smoke:
    command: "grep -q 'Backup created:' logs/deployment_$(date +%Y%m%d).log"
    expected_exit_code: 0

rollback: "N/A (backup operation)"

output:
  location: file
  path: "logs/deployment_$(date +%Y%m%d).log"
  ports:
    backup_confirmation:
      type: text

required_capabilities:
  - aws-cli
  - bash
```

#### T3.1.2: Push Updated Scripts

```yaml
task_id: T3.1.2
name: "Git push updated scripts and sync to server"
status: not_started
dependencies: [T3.1.1]

interface:
  input: "All updated and tested dispatch scripts"
  output: "Scripts deployed to server"

acceptance_criteria:
  - Git commit created with all changes
  - Commit pushed to GitHub main branch
  - Server pulls latest from GitHub
  - Scripts synced to /home/ubuntu/claude-executor/
  - Executable permissions verified

verification:
  smoke:
    command: "git log -1 --oneline | grep -q 'dispatch namespace fix'"
    expected_exit_code: 0

rollback: "git revert HEAD && git push"

output:
  location: file
  path: "logs/deployment_$(date +%Y%m%d).log"
  ports:
    push_log:
      type: text

required_capabilities:
  - git
  - aws-cli
```

#### T3.1.3: Verify Deployment

```yaml
task_id: T3.1.3
name: "Verify all scripts deployed correctly on server"
status: not_started
dependencies: [T3.1.2]

interface:
  input: "Deployment completion from T3.1.2"
  output: "Verification results"

acceptance_criteria:
  - All 6 scripts exist on server
  - All 6 scripts have execute permissions
  - Version numbers match expected (v1.5, v1.6)
  - Namespace stripping logic present in all scripts
  - Syntax validation passes for all scripts

verification:
  smoke:
    command: "grep -q 'All scripts verified' logs/deployment_$(date +%Y%m%d).log"
    expected_exit_code: 0

rollback: "Restore from T3.1.1 backup"

output:
  location: file
  path: "logs/deployment_$(date +%Y%m%d).log"
  ports:
    verification_results:
      type: text

required_capabilities:
  - aws-cli
  - bash
```

### T3.2: Update Documentation

```yaml
task_id: T3.2
name: "Update dispatch script documentation"
status: not_started
dependencies: [T3.1]

interface:
  input: "Deployed scripts, current documentation"
  output: "Updated AGENTS_README.md and troubleshooting guide"

acceptance_criteria:
  - AGENTS_README.md updated with namespace format support
  - Usage examples show both formats
  - Troubleshooting section added
  - Version history updated
  - Documentation pushed to GitHub

verification:
  smoke:
    command: "grep -q 'namespace' scripts/AGENTS_README.md"
    expected_exit_code: 0

rollback: "git restore scripts/AGENTS_README.md"

output:
  location: file
  path: "scripts/AGENTS_README.md"
  ports:
    documentation:
      type: markdown

required_capabilities:
  - git
  - markdown
```

#### T3.2.1: Update AGENTS_README.md

```yaml
task_id: T3.2.1
name: "Add namespace format documentation to AGENTS_README"
status: not_started
dependencies: [T3.1.3]

interface:
  input: "Current AGENTS_README.md"
  output: "Updated AGENTS_README.md"

acceptance_criteria:
  - Usage section updated with namespace examples
  - Both formats documented clearly
  - Examples use real repo names
  - Backward compatibility noted

verification:
  smoke:
    command: "grep -q 'rgsuarez/' scripts/AGENTS_README.md"
    expected_exit_code: 0

rollback: "git restore scripts/AGENTS_README.md"

output:
  location: file
  path: "scripts/AGENTS_README.md"
  ports:
    readme:
      type: markdown

required_capabilities:
  - markdown
```

#### T3.2.2: Add Troubleshooting Guide

```yaml
task_id: T3.2.2
name: "Add namespace troubleshooting section"
status: not_started
dependencies: [T3.2.1]

interface:
  input: "Updated AGENTS_README.md"
  output: "AGENTS_README.md with troubleshooting"

acceptance_criteria:
  - Troubleshooting section added
  - Common errors documented (empty workspace, rsync fail)
  - Solutions provided
  - Links to this blueprint

verification:
  smoke:
    command: "grep -q 'Troubleshooting' scripts/AGENTS_README.md"
    expected_exit_code: 0

rollback: "git restore scripts/AGENTS_README.md"

output:
  location: file
  path: "scripts/AGENTS_README.md"
  ports:
    troubleshooting:
      type: markdown

required_capabilities:
  - markdown
```

---

## Tier 4: Verification — Production Validation

### T4.1: Run awsaudit Test Query

```yaml
task_id: T4.1
name: "Execute real awsaudit query with namespaced format"
status: not_started
dependencies: [T3.1, T3.2]

interface:
  input: "Deployed scripts, AWS SSM access"
  output: "Test query results showing successful execution"

acceptance_criteria:
  - Query sent with 'rgsuarez/awsaudit' format
  - Workspace created successfully (no rsync errors)
  - Agent executes and returns results
  - No empty workspace errors
  - Changes detected or output captured

verification:
  smoke:
    command: "grep -q 'Status: success' logs/awsaudit_test_query_$(date +%Y%m%d).log"
    expected_exit_code: 0

rollback: "N/A (read-only test)"

output:
  location: file
  path: "logs/awsaudit_test_query_$(date +%Y%m%d).log"
  ports:
    query_results:
      type: text

required_capabilities:
  - aws-cli
  - bash
```

### T4.2: Verify Cache Behavior

```yaml
task_id: T4.2
name: "Verify cache update and workspace creation with namespace"
status: not_started
dependencies: [T4.1]

interface:
  input: "Test query results from T4.1"
  output: "Cache behavior analysis"

acceptance_criteria:
  - Cache updated correctly at /repos/awsaudit (not /repos/rgsuarez/awsaudit)
  - Workspace created from cache
  - Git operations succeeded
  - No path construction errors
  - Lock files created correctly

verification:
  smoke:
    command: "grep -q 'cache behavior verified' logs/awsaudit_test_query_$(date +%Y%m%d).log"
    expected_exit_code: 0

rollback: "N/A (read-only verification)"

output:
  location: file
  path: "logs/awsaudit_test_query_$(date +%Y%m%d).log"
  ports:
    cache_analysis:
      type: text

required_capabilities:
  - aws-cli
  - bash
```

### T4.3: Final Validation

```yaml
task_id: T4.3
name: "Run validation across all 5 agents with namespace format"
status: not_started
dependencies: [T4.2]

interface:
  input: "Deployed scripts, test results from T4.1-T4.2"
  output: "Final validation report"

acceptance_criteria:
  - All 5 agents tested with namespaced repos
  - All agents handle namespace correctly
  - No regressions detected
  - Performance metrics within normal range
  - Validation report generated

verification:
  smoke:
    command: "test -f logs/final_validation_$(date +%Y%m%d).log && grep -c 'Agent.*SUCCESS' logs/final_validation_$(date +%Y%m%d).log | grep -q '^5$'"
    expected_exit_code: 0

rollback: "N/A (read-only validation)"

output:
  location: file
  path: "logs/final_validation_$(date +%Y%m%d).log"
  ports:
    validation_report:
      type: text

required_capabilities:
  - aws-cli
  - bash
```

---

## Dependency Graph

```yaml
dependencies:
  # Tier 0 - Foundation
  T0.1.1:
    depends_on: []
  T0.1.2:
    depends_on: [T0.1.1]
  T0.1.3:
    depends_on: [T0.1.2]
  T0.1:
    depends_on: [T0.1.1, T0.1.2, T0.1.3]

  # Tier 1 - Implementation
  T1.1.1:
    depends_on: [T0.1.3]
  T1.1.2:
    depends_on: [T1.1.1]
  T1.1.3:
    depends_on: [T1.1.2]
  T1.1:
    depends_on: [T1.1.1, T1.1.2, T1.1.3]

  T1.2.1:
    depends_on: [T1.1.1]
  T1.2.2:
    depends_on: [T1.2.1]
  T1.2:
    depends_on: [T1.2.1, T1.2.2]

  T1.3:
    depends_on: [T1.1]
  T1.4:
    depends_on: [T1.1]
  T1.5:
    depends_on: [T1.1]
  T1.6:
    depends_on: [T1.1]

  # Tier 2 - Testing
  T2.1.1:
    depends_on: [T1.1]
  T2.1.2:
    depends_on: [T1.1]
  T2.1.3:
    depends_on: [T1.1]
  T2.1:
    depends_on: [T2.1.1, T2.1.2, T2.1.3]

  T2.2.1:
    depends_on: [T2.1]
  T2.2.2:
    depends_on: [T2.1]
  T2.2:
    depends_on: [T2.2.1, T2.2.2]

  T2.3:
    depends_on: [T2.2]

  # Tier 3 - Deployment
  T3.1.1:
    depends_on: [T2.3]
  T3.1.2:
    depends_on: [T3.1.1]
  T3.1.3:
    depends_on: [T3.1.2]
  T3.1:
    depends_on: [T3.1.1, T3.1.2, T3.1.3]

  T3.2.1:
    depends_on: [T3.1.3]
  T3.2.2:
    depends_on: [T3.2.1]
  T3.2:
    depends_on: [T3.2.1, T3.2.2]

  # Tier 4 - Verification
  T4.1:
    depends_on: [T3.1, T3.2]
  T4.2:
    depends_on: [T4.1]
  T4.3:
    depends_on: [T4.2]
```

**Visual Dependency Flow:**

```
T0.1.1 → T0.1.2 → T0.1.3 → T0.1
                              ↓
                    T1.1.1 → T1.1.2 → T1.1.3 → T1.1
                                                  ↓
                    ┌─────────────────────────────┼─────────────────────────┐
                    ↓                             ↓                         ↓
                  T1.2 (T1.2.1→T1.2.2)          T1.3                      T1.4
                    ↓                             ↓                         ↓
                  T1.5                          T1.6                        ↓
                    └─────────────────────────────┴─────────────────────────┘
                                                  ↓
                    T2.1 (T2.1.1, T2.1.2, T2.1.3)
                                ↓
                    T2.2 (T2.2.1, T2.2.2)
                                ↓
                              T2.3
                                ↓
                    T3.1 (T3.1.1→T3.1.2→T3.1.3)
                                ↓
                    T3.2 (T3.2.1→T3.2.2)
                                ↓
                    T4.1 → T4.2 → T4.3
```

---

## Document Control

### Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-01-11 | Claude Sonnet 4.5 | Initial blueprint creation |

### Change Log

- **2026-01-11**: Blueprint generated with depth=3 granularity per BSF v2.0.1 specification

### Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Technical Lead | Pending | — | — |
| Platform Owner | Pending | — | — |

---

## Estimated Effort

| Tier | Tasks | Estimated Time |
|------|-------|----------------|
| T0 | 4 tasks (3 subtasks) | 2 hours |
| T1 | 11 tasks (6 parent, 5 with subtasks) | 4 hours |
| T2 | 7 tasks (3 parent, 4 subtasks) | 3 hours |
| T3 | 5 tasks (2 parent, 3 subtasks) | 2 hours |
| T4 | 3 tasks | 1 hour |
| **Total** | **30 tasks** | **~12 hours** |

**Critical Path:** T0.1.1→T0.1.2→T0.1.3→T1.1.1→T1.1.2→T1.1.3→T2.1→T2.2→T2.3→T3.1→T4.1→T4.2→T4.3

**Parallelization Opportunities:**
- T1.2, T1.3, T1.4, T1.5, T1.6 can run in parallel after T1.1 completes
- T2.1.1, T2.1.2, T2.1.3 can run in parallel
- T2.2.1, T2.2.2 can run in parallel

---

**Blueprint Status:** Ready for execution
**Next Action:** Begin T0.1.1 (Document current behavior)
