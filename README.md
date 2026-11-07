# METABRIC disease investigation pipeline

## 1. What is this project?

This project is a small, reproducible statistical investigation using the
METABRIC breast-cancer dataset.

The central question is:

> Can simple combinations of clinical characteristics distinguish patients who
> died of the disease from patients who were living at the end of follow-up?

The project compares three rules based on:

- age at diagnosis;
- tumor size;
- tumor grade;
- the number of positive lymph nodes;
- the Nottingham Prognostic Index "NPI" (explained in details in step 3).

This is **not** a medical diagnosis tool and it does not prove that a
characteristic causes death. It only measures associations observed in this
dataset.

## 2. How the analysis works

The complete pipeline is launched with one command: `run.sh`.

### Step 1: Download and verify the data

The script downloads the public METABRIC archive, calculates its SHA-256
checksum, verifies the archive, and extracts the two clinical files needed by
the analysis. The raw archive is never modified.

### Step 2: Clean and join the clinical data

The patient and sample tables are joined using `PATIENT_ID`. A patient is kept
only when the required clinical values are available:

- age at diagnosis;
- tumor size;
- tumor grade;
- positive lymph nodes;
- a usable outcome.

The analysis keeps two outcome groups:

- `died`: the patient died of the disease;
- `living`: the patient was living.

Patients who died of other causes, or whose required values are missing, are
excluded. Therefore, the number of rows in `clean_clinical.tsv` is smaller
than the number of rows in the original dataset.

### Step 3: Apply the three predefined rules

Here, a **rule** is a simple question about a patient. It checks whether the
patient has certain values. For example, the question
`grade = 3 AND positive lymph nodes >= 4` is true for some patients and false
for others. The program compares the patients for whom the answer is true with
the patients for whom the answer is false.

Each rule divides the cleaned patients into two groups:

- **matching patients**: patients who satisfy the rule;
- **non-matching patients**: all other patients.

#### Rule A — Nottingham Prognostic Index

```text
NPI > 5.4
```

When NPI is unavailable, it is computed as:

```text
NPI = 0.2 × tumor size in cm + node stage + grade
```

The node stage is:

- `1` for 0 positive nodes;
- `2` for 1 to 3 positive nodes;
- `3` for 4 or more positive nodes.

#### Rule B — Grade and lymph nodes

```text
grade = 3 AND positive lymph nodes >= 4
```

#### Rule C — Age, size, grade and lymph nodes

```text
age >= 60
AND tumor size >= 25 mm
AND grade = 3
AND positive lymph nodes >= 1
```

These rules were fixed before interpreting the results. They are not learned
automatically from the data.

### Step 4: Compare the rule groups

For every rule, the program calculates:

- **Matched patients**: number of patients satisfying the rule.
- **Coverage**: matched patients divided by all analyzed patients.
- **Death rate (matched)**: deaths among matching patients.
- **Death rate (non-matched)**: deaths among non-matching patients.
- **Gap**: matched death rate minus non-matched death rate.
- **Risk ratio**: matched death rate divided by non-matched death rate.
- **Sensitivity**: proportion of all deaths captured by the rule.
- **Specificity**: proportion of living patients not captured by the rule.
- **P-value**: result of Fisher's exact test.

The Fisher test uses this 2 × 2 table:

|                     | Died |    Living |
|---                  |---:  |---:|
| Rule matches        | a    | b |
| Rule does not match | c |   d |

## 3. What makes a rule eligible?

A rule is **eligible** only when both conditions are true:

1. It matches at least `10` patients (`MIN_SIZE = 10`).
2. Its Fisher-test p-value is below the Bonferroni-corrected threshold.

There are three rules, so with `alpha = 0.05`:

```text
corrected threshold = 0.05 / 3 = 0.0167
```

The test is strict: the p-value must be **less than** `0.0167`.

The reported best rule is the eligible rule with the largest positive gap in
death rates. If no rule is eligible, the report says **No eligible rule**.

## 4. How to interpret the results

Suppose a rule has:

```text
Death rate (matched)     = 80%
Death rate (non-matched) = 50%
Gap                      = 30 percentage points
Risk ratio               = 1.6
```

This means that, in this dataset, more patients in the matching group died.
It does **not** mean that every patient matching the rule will die. It also
does not prove that the rule caused the deaths.

Read the columns like this:

- A positive **gap** means that the matching group had more deaths.
- A **risk ratio** above `1` means that the matching group had more deaths
  than the non matching group. For example, `1.6` means 1.6 times more in this
  dataset.
- A small **p-value** means that the difference is less likely to be due to
  chance according to the test.
- **Eligible = Yes** means that the rule matched at least 10 patients and
  passed the p-value test.
- A rule can have a large gap and still be **not eligible** if it matches too
  few patients.

For the current run, 103 patients remain after cleaning: 72 died of the
disease and 31 were living. Rule A and Rule B each match 13 patients and pass
the current eligibility criteria; Rule C matches 7 patients and is therefore
not eligible.

These numbers can change if the data or the settings change. Always read the
generated report for the results of the latest run.

## 5. Installation on another machine

The project can run on a Linux machine or on Windows through WSL. In both
cases, the project downloads the METABRIC data automatically; the data archive
does not need to be copied manually.

### Option A: Linux (Ubuntu or another Debian-based distribution)

Open a terminal and install Git, Bash, Python, and the command-line tools used
by the pipeline:

```bash
sudo apt update
sudo apt install -y git bash curl tar coreutils gawk grep
sudo apt install -y python3 python3-venv python3-pip
```

Clone the project and enter its directory. Replace the URL with the URL of the
GitHub repository:

```bash
git clone https://github.com/BMA91/sps-project-.git
cd YOUR_REPOSITORY
```

Create the Python virtual environment and install the required packages:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

If the project is already installed and only the environment is missing, run
the virtual-environment commands again from the project directory.

### Option B: Windows with WSL 2

Open PowerShell as Administrator and install WSL with Ubuntu:

```powershell
wsl --install -d Ubuntu-22.04
```

Restart Windows if requested. Open **Ubuntu** from the Start menu and create
your Linux username and password. Then install the required tools inside the
Ubuntu terminal:

```bash
sudo apt update
sudo apt install -y git bash curl tar coreutils gawk grep
sudo apt install -y python3 python3-venv python3-pip
```

Clone and install the project inside the Linux filesystem:

```bash
cd ~
git clone https://github.com/BMA91/sps-project-.git 
cd ~/sps
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Keep the project under `~/sps` (for example `/home/username/sps`) instead of
`/mnt/c` or `/mnt/d`. This avoids permission problems with `chmod` and is
usually faster for Linux scripts.

## 6. Running the project

Run these commands from the project directory, in the Ubuntu or Linux terminal:

```bash
cd ~/sps
. .venv/bin/activate
bash run.sh -h
bash run.sh -t
```

The `-t` option runs the complete analysis and then runs the automated tests.
The first run downloads the METABRIC archive, so it can take a few minutes.

Options:

- `-d DATA_DIR`: use another data directory;
- `-o OUT_DIR`: write results to another output directory;
- `-f`: force a new download of the raw archive;
- `-s`: reserved quick-sample option;
- `-t`: run the automated tests after the analysis;
- `-h`: display help.

To run the analysis without the tests:

```bash
bash run.sh
```

To download the data again from scratch:

```bash
bash run.sh -f -t
```

## 7. Understanding the generated files

After a successful run:

- `results/report.md`: readable explanation, rule definitions, result table and
  chart links;
- `results/rule_comparison_table.png`: readable image version of the results
  table;
- `results/death_rates.png`: death rates for matching and non-matching groups;
- `results/rule_metrics.png`: coverage, gap, sensitivity and specificity;
- `results/outcome_counts.png`: number of died and living patients;
- `results/rules_comparison.csv`: tabular results for spreadsheets;
- `results/summary.json`: machine-readable summary;
- `results/clean_clinical.tsv`: cleaned table used by the analysis;
- `logs/run_YYYYmmdd_HHMMSS.log`: execution log.

### Viewing results on Linux

From the project directory:

```bash
ls -lh results
cat results/report.md
```

On a desktop Linux installation, open the results folder with:

```bash
xdg-open results
```

Open the readable report in VS Code, if the `code` command is installed:

```bash
code results/report.md
```

### Viewing results on Windows with WSL

From the Ubuntu terminal, open the results folder in Windows Explorer:

```powershell
explorer.exe "$(wslpath -w "$PWD/results")"
```

Open the report in VS Code:

```bash
code results/report.md
```

You can also open a specific chart:

```bash
explorer.exe "$(wslpath -w "$PWD/results/rule_comparison_table.png")"
```

The main files to inspect are `report.md` and
`rule_comparison_table.png`. The report also links to all other charts.

## 8. Testing

The tests cover the rule thresholds and basic input-table behavior:

```bash
. .venv/bin/activate
pytest scripts/tests/test_analyze.py -q
```

The `-t` option runs these tests automatically after the analysis.

## 9. Repository structure

```text
.
├── README.md
├── SOP.md
├── SOURCES.md
├── requirements.txt
├── run.sh
├── data/
├── scripts/
│   ├── lib.sh
│   ├── download.sh
│   ├── clean.sh
│   ├── analyze.py
│   └── tests/
├── results/
├── logs/
├── cron/
└── docs/
```

## 10. Limits and responsible interpretation

- The dataset is observational; the analysis cannot establish causation.
- The rules are simple comparisons, not validated clinical prediction models.
- Patients with missing required values are excluded.
- Patients who died of other causes are excluded from the two analyzed groups.
- Follow-up time is not used to adjust the death rates.
- The current cleaned dataset is relatively small, so percentages can change
  substantially when only a few patients are added or removed.
- Statistical significance does not automatically mean clinical usefulness.
- Results must not be used to make decisions about an individual patient.
