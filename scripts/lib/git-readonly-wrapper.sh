#!/usr/bin/env bash

# Git read-only wrapper. Blocks commit/push in staging mode.

REAL_GIT="${GIT_REAL_PATH:-}"
if [[ -z "${REAL_GIT}" ]]; then
  REAL_GIT=$(command -v git)
fi

if [[ -z "${REAL_GIT}" ]]; then
  echo "git-readonly-wrapper: real git not found" >&2
  exit 127
fi

SUBCOMMAND="${1:-}"

if [[ "${GIT_READONLY_MODE:-0}" == "1" ]]; then
  case "$SUBCOMMAND" in
    commit|push)
      echo "🔒 READ-ONLY GIT: '$SUBCOMMAND' blocked in staging mode" >&2
      exit 1
      ;;
  esac
fi

exec "$REAL_GIT" "$@"
