#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$APP_ROOT/scripts/lib.sh"

DATA_DIR="$APP_ROOT/data"
FORCE_DOWNLOAD=0
ARCHIVE_URL="https://datahub.assets.cbioportal.org/brca_metabric.tar.gz"

usage() {
  cat <<'EOF'
Usage: download.sh -d DATA_DIR [-f]
EOF
}

while getopts ":hd:f" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    d) DATA_DIR="$OPTARG" ;;
    f) FORCE_DOWNLOAD=1 ;;
    :) echo "Option -$OPTARG requires a value." >&2; usage >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
  esac
done

mkdir -p "$DATA_DIR"
ARCHIVE_PATH="$DATA_DIR/brca_metabric.tar.gz"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
EXTRACT_DIR="$DATA_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

log "INFO" "Working directory: $APP_ROOT"

if [[ ! -f "$ARCHIVE_PATH" || "$FORCE_DOWNLOAD" -eq 1 ]]; then
  log "INFO" "Downloading METABRIC archive to $ARCHIVE_PATH"
  rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
  curl -L --fail --output "$ARCHIVE_PATH" "$ARCHIVE_URL"
  sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"
  log "INFO" "Downloaded and hashed $ARCHIVE_PATH"
else
  log "INFO" "Archive already present. Skipping download."
fi

check_file "$ARCHIVE_PATH"
verify_checksum "$ARCHIVE_PATH" "$CHECKSUM_PATH"
chmod a-w "$ARCHIVE_PATH"
chmod a-w "$CHECKSUM_PATH"

tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_DIR" --wildcards 'brca_metabric/data_clinical_patient.txt' 'brca_metabric/data_clinical_sample.txt'

if [[ -f "$EXTRACT_DIR/brca_metabric/data_clinical_patient.txt" ]]; then
  log "INFO" "Clinical patient file extracted successfully."
fi
if [[ -f "$EXTRACT_DIR/brca_metabric/data_clinical_sample.txt" ]]; then
  log "INFO" "Clinical sample file extracted successfully."
fi

printf '%s\n' "Download complete."
