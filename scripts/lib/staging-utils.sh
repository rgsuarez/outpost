#!/usr/bin/env bash

# Staging utilities for Outpost dispatch staging mode.
# Safe to source from other scripts.

if [[ -n "${_OUTPOST_STAGING_UTILS_LOADED:-}" ]]; then
  return 0
fi
_OUTPOST_STAGING_UTILS_LOADED=1

staging_now_utc() {
  date -u "+%Y-%m-%dT%H:%M:%SZ"
}

staging_root_default() {
  if [[ -n "${STAGING_ROOT:-}" ]]; then
    echo "${STAGING_ROOT}"
  else
    echo ".staging"
  fi
}

staging_entry_dir() {
  local command_id="$1"
  local root="$2"
  echo "${root%/}/inbox/${command_id}"
}

create_staging_inbox() {
  local command_id="$1"
  local root="$2"

  if [[ -z "${command_id}" || -z "${root}" ]]; then
    echo "create_staging_inbox: command_id and root required" >&2
    return 1
  fi

  local base="${root%/}"
  local inbox_dir="${base}/inbox"
  local entry_dir="${inbox_dir}/${command_id}"

  mkdir -p "${inbox_dir}" "${base}/processed" "${base}/failed"
  mkdir -p "${entry_dir}/outputs/entries" "${entry_dir}/outputs/artifacts"

  echo "${entry_dir}"
}

write_staging_manifest() {
  local command_id="$1"
  local worker_id="$2"
  local task_summary="$3"
  local root="$4"
  local task_id="${5:-}"
  local blueprint_id="${6:-}"
  local executor="${7:-}"
  local repo="${8:-}"
  local timestamp="${9:-$(staging_now_utc)}"

  if [[ -z "${command_id}" || -z "${worker_id}" || -z "${task_summary}" || -z "${root}" ]]; then
    echo "write_staging_manifest: command_id, worker_id, task_summary, root required" >&2
    return 1
  fi

  local entry_dir
  entry_dir=$(create_staging_inbox "${command_id}" "${root}") || return 1
  local tmp
  tmp=$(mktemp "${entry_dir}/manifest.json.tmp.XXXXXX") || return 1

  jq -n \
    --arg command_id "${command_id}" \
    --arg worker_id "${worker_id}" \
    --arg timestamp "${timestamp}" \
    --arg task_summary "${task_summary}" \
    --arg task_id "${task_id}" \
    --arg blueprint_id "${blueprint_id}" \
    --arg executor "${executor}" \
    --arg repo "${repo}" \
    '(
      {
        command_id: $command_id,
        worker_id: $worker_id,
        timestamp: $timestamp,
        task_summary: $task_summary
      }
      + (if ($task_id|length) > 0 then {task_id: $task_id} else {} end)
      + (if ($blueprint_id|length) > 0 then {blueprint_id: $blueprint_id} else {} end)
      + (if ($executor|length) > 0 then {executor: $executor} else {} end)
      + (if ($repo|length) > 0 then {repo: $repo} else {} end)
    )' > "${tmp}" && mv "${tmp}" "${entry_dir}/manifest.json"
}

write_staging_status() {
  local command_id="$1"
  local status="$2"
  local exit_code="$3"
  local duration_ms="$4"
  local root="$5"
  local started_at="${6:-}"
  local completed_at="${7:-$(staging_now_utc)}"
  local error_summary="${8:-}"

  if [[ -z "${command_id}" || -z "${status}" || -z "${exit_code}" || -z "${duration_ms}" || -z "${root}" ]]; then
    echo "write_staging_status: command_id, status, exit_code, duration_ms, root required" >&2
    return 1
  fi

  if [[ "${status}" != "complete" && "${status}" != "failed" ]]; then
    echo "write_staging_status: status must be complete or failed" >&2
    return 1
  fi

  local entry_dir
  entry_dir=$(create_staging_inbox "${command_id}" "${root}") || return 1
  local tmp
  tmp=$(mktemp "${entry_dir}/status.json.tmp.XXXXXX") || return 1

  jq -n \
    --arg status "${status}" \
    --argjson exit_code "${exit_code}" \
    --argjson duration_ms "${duration_ms}" \
    --arg started_at "${started_at}" \
    --arg completed_at "${completed_at}" \
    --arg error_summary "${error_summary}" \
    '(
      {
        status: $status,
        exit_code: $exit_code,
        duration_ms: $duration_ms
      }
      + (if ($started_at|length) > 0 then {started_at: $started_at} else {} end)
      + (if ($completed_at|length) > 0 then {completed_at: $completed_at} else {} end)
      + (if ($error_summary|length) > 0 then {error_summary: $error_summary} else {} end)
    )' > "${tmp}" && mv "${tmp}" "${entry_dir}/status.json"
}

write_staging_entry_command_result() {
  local entry_dir="$1"
  local worker_id="$2"
  local task_id="$3"
  local command="$4"
  local exit_code="$5"
  local stdout_content="$6"
  local stderr_content="$7"
  local timestamp="${8:-$(staging_now_utc)}"

  if [[ -z "${entry_dir}" || -z "${worker_id}" || -z "${command}" || -z "${exit_code}" ]]; then
    echo "write_staging_entry_command_result: entry_dir, worker_id, command, exit_code required" >&2
    return 1
  fi

  local entry_id
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    entry_id=$(cat /proc/sys/kernel/random/uuid)
  else
    entry_id=$(date +%s%N)
  fi

  local content_json
  content_json=$(jq -c -S -n \
    --arg command "${command}" \
    --argjson exit_code "${exit_code}" \
    --arg stdout "${stdout_content}" \
    --arg stderr "${stderr_content}" \
    '{command:$command, exit_code:$exit_code, stdout:$stdout, stderr:$stderr}')

  local checksum
  checksum="sha256:$(printf '%s' "${content_json}" | sha256sum | awk '{print $1}')"

  local entry_path="${entry_dir}/outputs/entries/${entry_id}.json"
  local tmp
  tmp=$(mktemp "${entry_path}.tmp.XXXXXX") || return 1

  jq -n \
    --arg entry_id "${entry_id}" \
    --arg worker_id "${worker_id}" \
    --arg task_id "${task_id}" \
    --arg timestamp "${timestamp}" \
    --arg checksum "${checksum}" \
    --argjson content "${content_json}" \
    '(
      {
        entry_id: $entry_id,
        worker_id: $worker_id,
        task_id: $task_id,
        timestamp: $timestamp,
        entry_type: "command_result",
        content: $content,
        checksum: $checksum
      }
    )' > "${tmp}" && mv "${tmp}" "${entry_path}"
}

validate_staging_entry() {
  local command_id="$1"
  local root="$2"

  if [[ -z "${command_id}" || -z "${root}" ]]; then
    echo "validate_staging_entry: command_id and root required" >&2
    return 1
  fi

  local entry_dir
  entry_dir=$(staging_entry_dir "${command_id}" "${root}")

  if [[ ! -d "${entry_dir}" ]]; then
    echo "validate_staging_entry: entry dir missing: ${entry_dir}" >&2
    return 1
  fi

  if [[ ! -d "${entry_dir}/outputs/entries" ]]; then
    echo "validate_staging_entry: outputs/entries missing" >&2
    return 1
  fi

  if [[ ! -f "${entry_dir}/manifest.json" ]]; then
    echo "validate_staging_entry: manifest.json missing" >&2
    return 1
  fi

  if [[ ! -f "${entry_dir}/status.json" ]]; then
    echo "validate_staging_entry: status.json missing" >&2
    return 1
  fi

  jq -e 'has("command_id") and has("worker_id") and has("timestamp") and has("task_summary")' \
    "${entry_dir}/manifest.json" >/dev/null

  jq -e 'has("status") and has("exit_code") and has("duration_ms") and (.status == "complete" or .status == "failed")' \
    "${entry_dir}/status.json" >/dev/null
}
