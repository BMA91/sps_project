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

# This pipeline normalizes the raw clinical files and turns them into a usable join key.
awk 'BEGIN{FS="\t"; OFS="\t"} $1 == "PATIENT_ID" {header=1} header {print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25}' "$PATIENT_FILE" | {
  IFS= read -r header
  printf '%s\n' "$header"
  sort -k1,1
} > "$TMP_DIR/patient.tsv"

awk 'BEGIN{FS="\t"; OFS="\t"} $1 == "PATIENT_ID" {header=1} header {print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13}' "$SAMPLE_FILE" | {
  IFS= read -r header
  printf '%s\n' "$header"
  sort -k1,1
} > "$TMP_DIR/sample.tsv"

python3 - "$TMP_DIR/patient.tsv" "$TMP_DIR/sample.tsv" "$OUT_PATH" <<'PY'
import csv
import os
import sys

pat_path, sam_path, out_path = sys.argv[1:4]

with open(pat_path, newline='') as f:
    patient_rows = list(csv.reader(f, delimiter='\t'))
with open(sam_path, newline='') as f:
    sample_rows = list(csv.reader(f, delimiter='\t'))

if not patient_rows or not sample_rows:
    raise SystemExit('Patient or sample table is empty after cleaning.')

p_header = patient_rows[0]
# A small, explicit mapping for the real METABRIC fields in the patient file.
patient_map = {
    'PATIENT_ID': 0,
    'AGE_AT_DIAGNOSIS': 12,
    'LYMPH_NODES_EXAMINED_POSITIVE': 1,
    'NPI': 2,
    'VITAL_STATUS': 18,
    'OS_STATUS': 14,
    'OS_MONTHS': 13,
}

s_header = sample_rows[0]
sample_map = {
    'PATIENT_ID': 0,
    'GRADE': 6,
    'TUMOR_SIZE': 10,
}

if 'PATIENT_ID' not in p_header or 'PATIENT_ID' not in s_header:
    raise SystemExit('Required patient/sample identifiers are missing from the extracted tables.')

# Keep only the columns we need.
patient_data = {}
for row in patient_rows[1:]:
    if len(row) <= max(patient_map.values()):
        continue
    pid = row[0].strip()
    if not pid:
        continue
    patient_data[pid] = row

sample_data = {}
for row in sample_rows[1:]:
    if len(row) <= max(sample_map.values()):
        continue
    pid = row[0].strip()
    if not pid:
        continue
    sample_data[pid] = row

records = []
for pid, pr in patient_data.items():
    if pid not in sample_data:
        continue
    sr = sample_data[pid]
    age = pr[patient_map['AGE_AT_DIAGNOSIS']].strip() if len(pr) > patient_map['AGE_AT_DIAGNOSIS'] else ''
    nodes = pr[patient_map['LYMPH_NODES_EXAMINED_POSITIVE']].strip() if len(pr) > patient_map['LYMPH_NODES_EXAMINED_POSITIVE'] else ''
    npi = pr[patient_map['NPI']].strip() if len(pr) > patient_map['NPI'] else ''
    vital = pr[patient_map['VITAL_STATUS']].strip() if len(pr) > patient_map['VITAL_STATUS'] else ''
    os_status = pr[patient_map['OS_STATUS']].strip() if len(pr) > patient_map['OS_STATUS'] else ''
    grade = sr[sample_map['GRADE']].strip() if len(sr) > sample_map['GRADE'] else ''
    tumor = sr[sample_map['TUMOR_SIZE']].strip() if len(sr) > sample_map['TUMOR_SIZE'] else ''
    if not age or not nodes or not grade or not tumor:
        continue
    value = (vital or os_status or '').upper()
    if 'LIVING' in value or value == '0:LIVING' or value == '0:NOT RECURRED':
        outcome = 'living'
    elif 'DECEASED' in value or 'DIED OF DISEASE' in value or 'DIED' in value or value == '1:DECEASED':
        outcome = 'died'
    else:
        outcome = 'exclude'
    if outcome == 'exclude':
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

final_records = []
for rec in records:
    missing = any(v in ['', 'NA', 'N/A', 'NAN', '[Not Available]', 'Not Available'] for v in [rec['AGE_AT_DIAGNOSIS'], rec['TUMOR_SIZE_MM'], rec['GRADE'], rec['LYMPH_NODES_POSITIVE']])
    if missing:
        continue
    final_records.append(rec)

# Count by outcome and save.
total = len(final_records)
count_died = sum(1 for r in final_records if r['OUTCOME'] == 'died')
count_living = sum(1 for r in final_records if r['OUTCOME'] == 'living')

print(f'Total patients after cleaning: {total}')
print(f'Final died count: {count_died}')
print(f'Final living count: {count_living}')

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow(['PATIENT_ID', 'AGE_AT_DIAGNOSIS', 'TUMOR_SIZE_MM', 'GRADE', 'LYMPH_NODES_POSITIVE', 'NPI', 'OUTCOME'])
    for rec in final_records:
        writer.writerow([
            rec['PATIENT_ID'],
            rec['AGE_AT_DIAGNOSIS'],
            rec['TUMOR_SIZE_MM'],
            rec['GRADE'],
            rec['LYMPH_NODES_POSITIVE'],
            rec['NPI'],
            rec['OUTCOME'],
        ])
PY

if [[ ! -s "$OUT_PATH" ]]; then
  die "Clean clinical output is empty: $OUT_PATH"
fi

awk -F'\t' 'NR==1{header=$0; next} { if (NF != 7) { print "Bad row: " NR ": " NF " columns" > "/dev/stderr"; exit 1; } } END { print "Clean table ok: " NR-1 " rows" }' "$OUT_PATH"

log "INFO" "Clean table prepared at $OUT_PATH"
