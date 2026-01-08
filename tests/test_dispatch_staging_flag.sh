#!/usr/bin/env bash
set -euo pipefail

SCRIPT="/home/richie/projects/outpost/scripts/dispatch-unified.sh"

if ! grep -q -- "--staging" "$SCRIPT"; then
  echo "--staging flag not found in dispatch-unified.sh" >&2
  exit 1
fi

# Usage output should mention staging
usage_output=$(bash "$SCRIPT" 2>&1 || true)
if ! echo "$usage_output" | grep -q -- "--staging"; then
  echo "Usage output missing --staging" >&2
  exit 1
fi

echo "staging flag test passed"
