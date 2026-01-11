#!/bin/bash
# Unit Test Suite for Dispatch Script Namespace Parsing
# Tests namespace stripping logic: "rgsuarez/repo" → "repo"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../../scripts"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test assertion function
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected: '$expected'"
        echo "  Got:      '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test function: namespace stripping logic
test_namespace_stripping() {
    local input="$1"
    local expected="$2"
    local test_name="$3"

    # Simulate the namespace stripping logic from dispatch scripts
    REPO_NAME="$input"
    if [[ "$REPO_NAME" == */* ]]; then
        REPO_NAME="${REPO_NAME##*/}"
    fi

    assert_equals "$expected" "$REPO_NAME" "$test_name"
}

echo "================================================"
echo "Namespace Parsing Unit Test Suite"
echo "================================================"
echo ""

echo "--- Test Group 1: With Namespace Prefix ---"
test_namespace_stripping "rgsuarez/awsaudit" "awsaudit" "Single namespace: rgsuarez/awsaudit → awsaudit"
test_namespace_stripping "rgsuarez/zeOS" "zeOS" "Single namespace: rgsuarez/zeOS → zeOS"
test_namespace_stripping "rgsuarez/outpost" "outpost" "Single namespace: rgsuarez/outpost → outpost"
test_namespace_stripping "github/username/repo" "repo" "Multiple namespaces: github/username/repo → repo"
test_namespace_stripping "org/team/project/repo" "repo" "Triple namespaces: org/team/project/repo → repo"
echo ""

echo "--- Test Group 2: Without Namespace (Backward Compatibility) ---"
test_namespace_stripping "awsaudit" "awsaudit" "Bare name: awsaudit → awsaudit (unchanged)"
test_namespace_stripping "zeOS" "zeOS" "Bare name: zeOS → zeOS (unchanged)"
test_namespace_stripping "outpost" "outpost" "Bare name: outpost → outpost (unchanged)"
test_namespace_stripping "my-project-2024" "my-project-2024" "Bare name with hyphens: my-project-2024 → my-project-2024"
test_namespace_stripping "aws.audit" "aws.audit" "Bare name with dot: aws.audit → aws.audit"
echo ""

echo "--- Test Group 3: Edge Cases ---"
test_namespace_stripping "rgsuarez/awsaudit/" "" "Trailing slash: rgsuarez/awsaudit/ → empty (bash behavior)"
test_namespace_stripping "/awsaudit" "awsaudit" "Leading slash: /awsaudit → awsaudit"
test_namespace_stripping "rgsuarez/" "" "Namespace only with slash: rgsuarez/ → empty"
test_namespace_stripping "rgsuarez/my-repo-name" "my-repo-name" "Hyphenated repo: rgsuarez/my-repo-name → my-repo-name"
test_namespace_stripping "rgsuarez/repo.name" "repo.name" "Dotted repo: rgsuarez/repo.name → repo.name"
test_namespace_stripping "rgsuarez/repo_name" "repo_name" "Underscored repo: rgsuarez/repo_name → repo_name"
test_namespace_stripping "rgsuarez/UPPERCASE" "UPPERCASE" "Uppercase repo: rgsuarez/UPPERCASE → UPPERCASE"
echo ""

echo "================================================"
echo "Test Results Summary"
echo "================================================"
echo "Total tests run:    $TESTS_RUN"
echo -e "Tests passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
