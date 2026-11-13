#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$APP_ROOT/scripts/lib.sh"

DATA_DIR="$APP_ROOT/data"
OUT_PATH="$APP_ROOT/results/clean_clinical.tsv"

usage() {
  cat <<'EOF'
Usage: clean.sh -d DATA_DIR -o OUTPUT_TSV
EOF
}

while getopts ":hd:o:" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    d) DATA_DIR="$OPTARG" ;;
    o) OUT_PATH="$OPTARG" ;;
    :) echo "Option -$OPTARG requires a value." >&2; usage >&2; exit 2 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
  esac
done

PATIENT_FILE="$DATA_DIR/extracted/brca_metabric/data_clinical_patient.txt"
SAMPLE_FILE="$DATA_DIR/extracted/brca_metabric/data_clinical_sample.txt"
check_file "$PATIENT_FILE"
check_file "$SAMPLE_FILE"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# This pipeline removes cBioPortal comments, sorts records by patient id, and
# removes duplicate consecutive records before the Python join.
awk 'BEGIN{FS="\t"; OFS="\t"} $1 == "PATIENT_ID" {next} /^#/ {next} {print}' "$PATIENT_FILE" |
  sed '/^$/d' |
  sort -t $'\t' -k1,1 |
  awk -F'\t' '!seen[$1]++ {print} seen[$1] > 1 {exit 1}' > "$TMP_DIR/patient.data"
awk '$1 == "PATIENT_ID" {print; exit}' "$PATIENT_FILE" > "$TMP_DIR/patient.header"
cat "$TMP_DIR/patient.header" "$TMP_DIR/patient.data" > "$TMP_DIR/patient.tsv"

awk 'BEGIN{FS="\t"; OFS="\t"} $1 == "PATIENT_ID" {next} /^#/ {next} {print}' "$SAMPLE_FILE" |
  sed '/^$/d' |
  sort -t $'\t' -k1,1 |
  awk -F'\t' '!seen[$1]++ {print} seen[$1] > 1 {exit 1}' > "$TMP_DIR/sample.data"
awk '$1 == "PATIENT_ID" {print; exit}' "$SAMPLE_FILE" > "$TMP_DIR/sample.header"
cat "$TMP_DIR/sample.header" "$TMP_DIR/sample.data" > "$TMP_DIR/sample.tsv"

python3 - "$TMP_DIR/patient.tsv" "$TMP_DIR/sample.tsv" "$OUT_PATH" <<'PY'
import csv
import os
import sys

pat_path, sam_path, out_path = sys.argv[1:4]

with open(pat_path, newline='', encoding='utf-8') as f:
    patient_rows = list(csv.reader(f, delimiter='\t'))
with open(sam_path, newline='', encoding='utf-8') as f:
    sample_rows = list(csv.reader(f, delimiter='\t'))

if not patient_rows or not sample_rows:
    raise SystemExit('Patient or sample table is empty after cleaning.')

def column_map(header, required, table_name):
    positions = {name: index for index, name in enumerate(header)}
    missing = [name for name in required if name not in positions]
    if missing:
        raise SystemExit(
            f'{table_name} is missing required columns: {", ".join(missing)}'
        )
    return positions

p_header = patient_rows[0]
patient_map = column_map(
    p_header,
    ['PATIENT_ID', 'AGE_AT_DIAGNOSIS', 'LYMPH_NODES_EXAMINED_POSITIVE',
     'NPI', 'VITAL_STATUS', 'OS_STATUS'],
    'Patient table',
)

s_header = sample_rows[0]
sample_map = column_map(s_header, ['PATIENT_ID', 'GRADE', 'TUMOR_SIZE'], 'Sample table')

def value(row, positions, name):
    index = positions[name]
    return row[index].strip() if index < len(row) else ''

def is_missing(value):
    return value.strip().upper() in {
        '', 'NA', 'N/A', 'NAN', '[NOT AVAILABLE]', 'NOT AVAILABLE',
    }

patient_data = {}
for row in patient_rows[1:]:
    pid = value(row, patient_map, 'PATIENT_ID')
    if pid:
        if pid in patient_data:
            raise SystemExit(f'Duplicate patient id: {pid}')
        patient_data[pid] = row

sample_data = {}
for row in sample_rows[1:]:
    pid = value(row, sample_map, 'PATIENT_ID')
    if pid:
        if pid in sample_data:
            raise SystemExit(f'Duplicate sample id: {pid}')
        sample_data[pid] = row

joined = 0
missing_required = 0
excluded_outcome = 0
records = []
for pid, patient_row in patient_data.items():
    if pid not in sample_data:
        continue
    joined += 1
    sample_row = sample_data[pid]
    age = value(patient_row, patient_map, 'AGE_AT_DIAGNOSIS')
    nodes = value(patient_row, patient_map, 'LYMPH_NODES_EXAMINED_POSITIVE')
    npi = value(patient_row, patient_map, 'NPI')
    vital = value(patient_row, patient_map, 'VITAL_STATUS')
    os_status = value(patient_row, patient_map, 'OS_STATUS')
    grade = value(sample_row, sample_map, 'GRADE')
    tumor = value(sample_row, sample_map, 'TUMOR_SIZE')
    required_values = [age, tumor, grade, nodes]
    if any(is_missing(item) for item in required_values):
        missing_required += 1
        continue
    outcome_value = (vital or os_status).upper()
    if outcome_value == 'LIVING' or outcome_value == '0:LIVING':
        outcome = 'living'
    elif outcome_value == 'DIED OF DISEASE':
        outcome = 'died'
    else:
        excluded_outcome += 1
        continue
    records.append({
        'PATIENT_ID': pid,
        'AGE_AT_DIAGNOSIS': age,
        'TUMOR_SIZE_MM': tumor,
        'GRADE': grade,
        'LYMPH_NODES_POSITIVE': nodes,
        'NPI': npi,
        'OUTCOME': outcome,
    })

count_died = sum(record['OUTCOME'] == 'died' for record in records)
count_living = sum(record['OUTCOME'] == 'living' for record in records)
print(f'Joined patients: {joined}')
print(f'After removing missing required values: {joined - missing_required}')
print(f'Excluded non-target outcomes: {excluded_outcome}')
print(f'Final patients: {len(records)}')
print(f'Final died count: {count_died}')
print(f'Final living count: {count_living}')

out_dir = os.path.dirname(out_path)
if out_dir:
    os.makedirs(out_dir, exist_ok=True)
with open(out_path, 'w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(
        f,
        fieldnames=['PATIENT_ID', 'AGE_AT_DIAGNOSIS', 'TUMOR_SIZE_MM',
                    'GRADE', 'LYMPH_NODES_POSITIVE', 'NPI', 'OUTCOME'],
        delimiter='\t',
    )
    writer.writeheader()
    writer.writerows(records)
PY

if [[ ! -s "$OUT_PATH" ]]; then
  die "Clean clinical output is empty: $OUT_PATH"
fi

awk -F'\t' 'NR==1{header=$0; next} { if (NF != 7) { print "Bad row: " NR ": " NF " columns" > "/dev/stderr"; exit 1; } } END { print "Clean table ok: " NR-1 " rows" }' "$OUT_PATH"

log "INFO" "Clean table prepared at $OUT_PATH"
