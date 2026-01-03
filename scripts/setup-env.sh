#!/bin/bash
# setup-env.sh - Set up Outpost environment variables
# Run once after deployment: source /home/ubuntu/claude-executor/setup-env.sh
# Or add to .bashrc: echo 'source /home/ubuntu/claude-executor/setup-env.sh' >> ~/.bashrc

# GitHub token - REQUIRED for all operations
# Set this to your actual token (this is a placeholder)
export GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Agent timeout in seconds (default 10 minutes)
export AGENT_TIMEOUT="${AGENT_TIMEOUT:-600}"

# Validate on source
if [[ -z "$GITHUB_TOKEN" && "$0" != "-bash" ]]; then
    echo "⚠️  GITHUB_TOKEN not set. Set it before running dispatch commands:"
    echo "   export GITHUB_TOKEN='your-token-here'"
fi
