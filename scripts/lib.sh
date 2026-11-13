#!/usr/bin/env bash
set -u

APP_ROOT="${APP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${LOG_FILE:-}"

log() {
  local level="${1:-INFO}"
  shift || true
  local message="${*:-}"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '%s [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
  fi

  printf '%s [%s] %s\n' "$timestamp" "$level" "$message"
}

die() {
  local message="${1:-Error}"
  local code="${2:-1}"
  log "ERROR" "$message"
  echo "ERROR: $message" >&2
  exit "$code"
}

check_file() {
  local path="${1:-}"
  [[ -n "$path" ]] || die "Missing file path in check_file"
  [[ -f "$path" ]] || die "Missing file: $path"
  [[ -s "$path" ]] || die "Empty file: $path"
}

verify_checksum() {
  local file="${1:-}"
  local checksum_file="${2:-}"
  [[ -n "$file" ]] || die "No file provided to verify_checksum"
  [[ -n "$checksum_file" ]] || die "No checksum file provided to verify_checksum"
  check_file "$file"
  check_file "$checksum_file"
  if ! (cd "$(dirname "$file")" && sha256sum -c "$checksum_file" >/dev/null 2>&1); then
    die "Checksum mismatch for $file. Re-run with -f to force a fresh download."
  fi
  log "INFO" "Checksum verification passed for $file"
}
