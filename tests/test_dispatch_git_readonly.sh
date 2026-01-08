#!/usr/bin/env bash
set -euo pipefail

WRAPPER_SRC="/home/richie/projects/outpost/scripts/lib/git-readonly-wrapper.sh"
if [[ ! -f "$WRAPPER_SRC" ]]; then
  echo "git-readonly-wrapper.sh not found" >&2
  exit 1
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

cd "$ROOT"

git init >/dev/null

echo "first" > file.txt
git add file.txt
git commit -m "initial" >/dev/null

# Prepare wrapper
WRAP_DIR=$(mktemp -d)
trap 'rm -rf "$WRAP_DIR"' EXIT
cp "$WRAPPER_SRC" "$WRAP_DIR/git"
chmod +x "$WRAP_DIR/git"

export GIT_REAL_PATH="$(command -v git)"
export GIT_READONLY_MODE=1
export PATH="$WRAP_DIR:$PATH"

# Read-only commands should work
if ! git status >/dev/null; then
  echo "git status failed in read-only mode" >&2
  exit 1
fi

# Write should be blocked

echo "change" >> file.txt
git add file.txt

set +e
commit_output=$(git commit -m "blocked" 2>&1)
exit_code=$?
set -e

if [[ $exit_code -eq 0 ]]; then
  echo "git commit unexpectedly succeeded in read-only mode" >&2
  exit 1
fi

if ! echo "$commit_output" | grep -q "READ-ONLY"; then
  echo "expected READ-ONLY warning not found" >&2
  exit 1
fi

echo "git read-only wrapper test passed"
