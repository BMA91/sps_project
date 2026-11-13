#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$SCRIPT_DIR"
DATA_DIR="$APP_ROOT/data"
OUT_DIR="$APP_ROOT/results"
FORCE_DOWNLOAD=0
SMALL_SAMPLE=0
RUN_TESTS=0
LOG_FILE=""
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: ./run.sh [-d DATA_DIR] [-o OUT_DIR] [-f] [-s] [-t] [-h]

Runs the METABRIC disease investigation pipeline.

Options:
  -d DATA_DIR   Use a custom data directory.
  -o OUT_DIR    Write results to a custom output directory.
  -f            Force a fresh download of the raw archive.
  -s            Small sample mode for quicker checks.
  -t            Run pytest after analysis.
  -h            Show this help text.
EOF
}

cleanup() {
  local status=$?
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
    printf '%s [INFO] Run finished with exit code %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$status" >> "$LOG_FILE"
  fi
}

trap cleanup EXIT
trap 'echo "Interrupted by user." >&2; exit 130' INT TERM

while getopts ":hd:o:fst" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    d) DATA_DIR="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    f) FORCE_DOWNLOAD=1 ;;
    s) SMALL_SAMPLE=1 ;;
    t) RUN_TESTS=1 ;;
    :) echo "Option -$OPTARG requires a value." >&2; usage >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$APP_ROOT/logs" "$APP_ROOT/results" "$DATA_DIR" "$OUT_DIR"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="$APP_ROOT/logs/run_${TIMESTAMP}.log"
TMP_DIR="$(mktemp -d)"
printf '%s [INFO] Starting METABRIC pipeline\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"

export APP_ROOT DATA_DIR OUT_DIR FORCE_DOWNLOAD SMALL_SAMPLE LOG_FILE TMP_DIR

if [[ ! -d "$APP_ROOT/.venv" ]]; then
  python3 -m venv "$APP_ROOT/.venv"
  "$APP_ROOT/.venv/bin/pip" install -r "$APP_ROOT/requirements.txt"
fi

if [[ "$FORCE_DOWNLOAD" -eq 1 ]]; then
  bash "$APP_ROOT/scripts/download.sh" -d "$DATA_DIR" -f 2>&1 | tee -a "$LOG_FILE"
else
  bash "$APP_ROOT/scripts/download.sh" -d "$DATA_DIR" 2>&1 | tee -a "$LOG_FILE"
fi

bash "$APP_ROOT/scripts/clean.sh" -d "$DATA_DIR" -o "$OUT_DIR/clean_clinical.tsv" 2>&1 | tee -a "$LOG_FILE"

PYTHON_BIN="$APP_ROOT/.venv/bin/python"

if [[ "$SMALL_SAMPLE" -eq 1 ]]; then
  "$PYTHON_BIN" "$APP_ROOT/scripts/analyze.py" --clean-table "$OUT_DIR/clean_clinical.tsv" --output-dir "$OUT_DIR" --min-size 100 --alpha 0.05 --sample 100 2>&1 | tee -a "$LOG_FILE"
else
  "$PYTHON_BIN" "$APP_ROOT/scripts/analyze.py" --clean-table "$OUT_DIR/clean_clinical.tsv" --output-dir "$OUT_DIR" --min-size 100 --alpha 0.05 2>&1 | tee -a "$LOG_FILE"
fi

if [[ "$RUN_TESTS" -eq 1 ]]; then
  if [[ -d "$APP_ROOT/.venv" ]]; then
    TEST_PYTHON="$APP_ROOT/.venv/bin/python"
  else
    TEST_PYTHON="$PYTHON_BIN"
  fi
  "$TEST_PYTHON" -m pytest "$APP_ROOT/scripts/tests/test_analyze.py" -q 2>&1 | tee -a "$LOG_FILE"
fi

ARCHIVE_DATE="$(date '+%Y%m%d')"
RESULT_ARCHIVE="$OUT_DIR/results_${ARCHIVE_DATE}.tar.gz"
RESULT_CHECKSUM="$RESULT_ARCHIVE.sha256"
tar -czf "$RESULT_ARCHIVE" -C "$OUT_DIR" \
  clean_clinical.tsv rules_comparison.csv summary.json report.md \
  rule_comparison_table.png death_rates.png rule_metrics.png outcome_counts.png
sha256sum "$RESULT_ARCHIVE" > "$RESULT_CHECKSUM"
printf '%s [INFO] Results archived at %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$RESULT_ARCHIVE" | tee -a "$LOG_FILE"

printf '%s [INFO] Pipeline completed successfully.\n' "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
