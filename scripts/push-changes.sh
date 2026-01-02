#!/bin/bash
# push-changes.sh - Commit and push changes from an Outpost repo
#
# Usage: ./push-changes.sh <repo> [commit-message]
#
# Example: ./push-changes.sh swords-of-chaos-reborn "Fix combat damage calculation"

REPO=$1
MESSAGE=${2:-"Changes from Outpost Claude Code executor"}
REPO_DIR="/home/ubuntu/claude-executor/repos/$REPO"

if [ ! -d "$REPO_DIR" ]; then
    echo "ERROR: Repo $REPO not found at $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR"

if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to push in $REPO"
    exit 0
fi

echo "=== Changes to commit ==="
git status --short
echo ""

git add -A
git commit -m "$MESSAGE"
git push origin main

echo ""
echo "=== Pushed to origin/main ==="
git log -1 --oneline
