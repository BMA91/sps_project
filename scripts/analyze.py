#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import pandas as pd
from scipy.stats import fisher_exact


def parse_args():
    parser = argparse.ArgumentParser(description='Analyze clinical rules for METABRIC disease risk.')
    parser.add_argument('--clean-table', required=True, help='Clean clinical TSV file')
    parser.add_argument('--output-dir', required=True, help='Directory for CSV, summary JSON and figure')
    parser.add_argument('--min-size', type=int, default=10, help='Minimum matching patients to keep a rule')
    parser.add_argument('--alpha', type=float, default=0.05, help='Nominal significance threshold before Bonferroni correction')
    parser.add_argument('--sample', type=int, default=None, help='Optional sample size for quick testing')
    return parser.parse_args()


def npi_from_size_nodes_grade(size_mm, nodes, grade):
    try:
        size_cm = float(size_mm) / 10.0
        node_stage = 1 if float(nodes) == 0 else 2 if float(nodes) <= 3 else 3
        grade_value = float(grade)
        return 0.2 * size_cm + node_stage + grade_value
    except (TypeError, ValueError):
        return float('nan')


def rule_npi(row):
    npi = row.get('NPI')
    if pd.isna(npi):
        npi = npi_from_size_nodes_grade(row.get('TUMOR_SIZE_MM'), row.get('LYMPH_NODES_POSITIVE'), row.get('GRADE'))
    return pd.notna(npi) and float(npi) > 5.4


def rule_b(row):
    grade = row.get('GRADE')
    nodes = row.get('LYMPH_NODES_POSITIVE')
    try:
        return float(grade) == 3 and float(nodes) >= 4
    except (TypeError, ValueError):
        return False


def rule_c(row):
    age = row.get('AGE_AT_DIAGNOSIS')
    size = row.get('TUMOR_SIZE_MM')
    grade = row.get('GRADE')
    nodes = row.get('LYMPH_NODES_POSITIVE')
    try:
        return float(age) >= 60 and float(size) >= 25 and float(grade) == 3 and float(nodes) >= 1
    except (TypeError, ValueError):
        return False


def fisher_2x2(a, b, c, d):
    table = [[a, b], [c, d]]
    odds, pvalue = fisher_exact(table, alternative='two-sided')
    return pvalue, odds


def evaluate_rule(df, name, description, predicate, min_size, corrected_alpha):
    match_mask = df.apply(predicate, axis=1)
    matched = df[match_mask]
    non_matched = df[~match_mask]
    a = int((matched['OUTCOME'] == 'died').sum())
    b = int((matched['OUTCOME'] == 'living').sum())
    c = int((non_matched['OUTCOME'] == 'died').sum())
    d = int((non_matched['OUTCOME'] == 'living').sum())
    total = a + b + c + d
    coverage = 0.0 if total == 0 else (a + b) / total
    death_rate_match = 0.0 if (a + b) == 0 else a / (a + b)
    death_rate_non = 0.0 if (c + d) == 0 else c / (c + d)
    gap = death_rate_match - death_rate_non
    rr = 0.0 if death_rate_non == 0 else death_rate_match / death_rate_non
    sens = 0.0 if a + c == 0 else a / (a + c)
    spec = 0.0 if b + d == 0 else d / (b + d)
    pvalue, odds = fisher_2x2(a, b, c, d)
    corrected_alpha = 0.05 / 3.0
    eligible = (a + b) >= min_size and pvalue < corrected_alpha
    return {
        'rule': name,
        'description': description,
        'matched_patients': a + b,
        'coverage': coverage,
        'death_rate_match': death_rate_match,
        'death_rate_non_match': death_rate_non,
        'gap_points': gap,
        'risk_ratio': rr,
        'sensitivity': sens,
        'specificity': spec,
        'p_value': pvalue,
        'odds_ratio': odds,
        'eligible': bool(eligible),
        'a': a,
        'b': b,
        'c': c,
        'd': d,
    }


def write_report(output_dir, summary, results):
    def percentage(value):
        return f'{value:.1%}'

    def number(value):
        return f'{value:.3f}'

    lines = [
        '# METABRIC disease investigation results',
        '',
        '## Overview',
        '',
        f"- Patients analyzed: **{summary['n_patients']}**",
        f"- Died of disease: **{summary['n_died']}**",
        f"- Living: **{summary['n_living']}**",
        f"- Minimum matching patients: **{summary['min_size']}**",
        f"- Bonferroni-corrected significance threshold: **{summary['corrected_alpha']:.4f}**",
        '',
        f"## Best rule: {summary['best_rule']}",
        '',
        'The best rule is ranked by the largest difference in death rate among '
        'eligible rules. Eligibility requires the minimum sample size and a '
        'statistically significant Fisher exact test. If no rule is eligible, '
        'the report says so instead of presenting an unqualified winner.',
        '',
        '## Rule definitions and results',
        '',
        '| Rule | Definition | Matched | Coverage | Death rate (matched) | Death rate (non-matched) | Gap | Risk ratio | P-value | Eligible |',
        '|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|',
    ]
    for result in results:
        lines.append(
            f"| {result['rule']} | {result['description']} | "
            f"{result['matched_patients']} | {percentage(result['coverage'])} | "
            f"{percentage(result['death_rate_match'])} | "
            f"{percentage(result['death_rate_non_match'])} | "
            f"{percentage(result['gap_points'])} | {number(result['risk_ratio'])} | "
            f"{result['p_value']:.4g} | {'Yes' if result['eligible'] else 'No'} |"
        )
    lines.extend([
        '',
        '## Charts',
        'in order to open the charts, you can copy and paste them into your browser. or run the command in the terminal to open them in Windows Explorer.',
        '',
        '![Rule comparison table](rule_comparison_table.png)',
        'explorer.exe "\\\\wsl$\\Ubuntu-22.04\\home\\amine\\sps\\results\\rule_comparison_table.png"',
        '',
        '![Death rates by rule](death_rates.png)',
        'explorer.exe "\\\\wsl$\\Ubuntu-22.04\\home\\amine\\sps\\results\\death_rates.png"',
        '',
        '![Rule performance metrics](rule_metrics.png)',
        'explorer.exe "\\\\wsl$\\Ubuntu-22.04\\home\\amine\\sps\\results\\rule_metrics.png"',
        '',
        '![Analyzed outcomes](outcome_counts.png)',
        'explorer.exe "\\\\wsl$\\Ubuntu-22.04\\home\\amine\\sps\\results\\outcome_counts.png"',
        '',
        '## Interpretation',
        '',
        'A positive gap means the patients matching the rule had a higher observed '
        'death rate than the patients not matching it. These are associations in '
        'this dataset, not clinical predictions or causal conclusions.',
    ])
    (output_dir / 'report.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def save_charts(output_dir, df, results):
    labels = [result['rule'] for result in results]
    x = range(len(labels))

    table_rows = []
    for result in results:
        table_rows.append([
            result['rule'],
            result['description'],
            str(result['matched_patients']),
            f"{result['coverage']:.1%}",
            f"{result['death_rate_match']:.1%}",
            f"{result['death_rate_non_match']:.1%}",
            f"{result['gap_points']:.1%}",
            f"{result['risk_ratio']:.3f}",
            f"{result['p_value']:.4g}",
            'Yes' if result['eligible'] else 'No',
        ])
    headers = [
        'Rule', 'Definition', 'Matched', 'Coverage', 'Death rate\nmatched',
        'Death rate\nnon-matched', 'Gap', 'Risk ratio', 'P-value', 'Eligible',
    ]
    figure, axis = plt.subplots(figsize=(18, 3.8))
    axis.axis('off')
    table = axis.table(
        cellText=table_rows,
        colLabels=headers,
        colWidths=[0.07, 0.28, 0.07, 0.08, 0.10, 0.11, 0.07, 0.08, 0.07, 0.07],
        cellLoc='center',
        loc='center',
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1, 2.2)
    for cell in table.get_celld().values():
        cell.set_edgecolor('#bbbbbb')
    for column in range(len(headers)):
        table[(0, column)].set_facecolor('#d9eaf7')
        table[(0, column)].set_text_props(weight='bold')
    for row in range(1, len(table_rows) + 1):
        table[(row, 1)].get_text().set_ha('left')
    axis.set_title('METABRIC rule comparison', pad=18, weight='bold')
    figure.tight_layout()
    figure.savefig(output_dir / 'rule_comparison_table.png', dpi=180, bbox_inches='tight')
    plt.close(figure)

    plt.figure(figsize=(9, 5))
    plt.bar([i - 0.2 for i in x], [r['death_rate_match'] for r in results],
            width=0.35, color='tab:red', label='Matching patients')
    plt.bar([i + 0.2 for i in x], [r['death_rate_non_match'] for r in results],
            width=0.35, color='tab:blue', label='Non-matching patients')
    plt.axhline(df['OUTCOME'].eq('died').mean(), color='black', linestyle='--',
                linewidth=1.5, label='Overall death rate')
    plt.xticks(list(x), labels, rotation=20, ha='right')
    plt.ylabel('Death rate')
    plt.title('Death rates by rule')
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_dir / 'death_rates.png', dpi=150)
    plt.close()

    metrics = ['coverage', 'gap_points', 'sensitivity', 'specificity']
    metric_labels = ['Coverage', 'Death-rate gap', 'Sensitivity', 'Specificity']
    plt.figure(figsize=(9, 5))
    for index, result in enumerate(results):
        values = [result[metric] for metric in metrics]
        plt.plot(metric_labels, values, marker='o', label=result['rule'])
    plt.ylim(0, 1)
    plt.ylabel('Proportion')
    plt.title('Rule performance metrics')
    plt.legend()
    plt.tight_layout()
    plt.savefig(output_dir / 'rule_metrics.png', dpi=150)
    plt.close()

    plt.figure(figsize=(6, 5))
    counts = [int(df['OUTCOME'].eq('died').sum()), int(df['OUTCOME'].eq('living').sum())]
    bars = plt.bar(['Died of disease', 'Living'], counts, color=['tab:red', 'tab:green'])
    plt.ylabel('Patients')
    plt.title('Analyzed patient outcomes')
    for bar, count in zip(bars, counts):
        plt.text(bar.get_x() + bar.get_width() / 2, count, str(count),
                 ha='center', va='bottom')
    plt.tight_layout()
    plt.savefig(output_dir / 'outcome_counts.png', dpi=150)
    plt.close()


def main():
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(args.clean_table, sep='\t', dtype=str)
    df['OUTCOME'] = df['OUTCOME'].str.strip().str.lower()
    if args.sample is not None:
        df = df.head(args.sample).copy()

    df = df[df['OUTCOME'].isin(['died', 'living'])].copy()
    for col in ['AGE_AT_DIAGNOSIS', 'TUMOR_SIZE_MM', 'GRADE', 'LYMPH_NODES_POSITIVE', 'NPI']:
        df[col] = pd.to_numeric(df[col], errors='coerce')
    rule_definitions = [
        ('Rule A', 'NPI > 5.4: Nottingham Prognostic Index above 5.4',
         rule_npi),
        ('Rule B', 'Grade = 3 AND at least 4 positive lymph nodes', rule_b),
        ('Rule C', 'Age >= 60 AND tumor size >= 25 mm AND grade = 3 AND at least 1 positive lymph node',
         rule_c),
    ]
    corrected_alpha = args.alpha / len(rule_definitions)
    results = [
        evaluate_rule(df, name, description, predicate, args.min_size, corrected_alpha)
        for name, description, predicate in rule_definitions
    ]

    eligible_results = [result for result in results if result['eligible']]
    ranked = sorted(eligible_results, key=lambda r: r['gap_points'], reverse=True)
    summary = {
        'n_patients': int(len(df)),
        'n_died': int(df['OUTCOME'].eq('died').sum()),
        'n_living': int(df['OUTCOME'].eq('living').sum()),
        'min_size': args.min_size,
        'alpha': args.alpha,
        'corrected_alpha': corrected_alpha,
        'best_rule': ranked[0]['rule'] if ranked else 'No eligible rule',
        'rules': results,
    }

    csv_path = output_dir / 'rules_comparison.csv'
    pd.DataFrame(results).to_csv(csv_path, index=False)

    with open(output_dir / 'summary.json', 'w', encoding='utf-8') as f:
        json.dump(summary, f, indent=2)

    save_charts(output_dir, df, results)
    write_report(output_dir, summary, results)

    if ranked:
        print('Best rule:', ranked[0]['rule'])
        print('Coverage:', ranked[0]['coverage'])
        print('Gap in death rate:', ranked[0]['gap_points'])
        print('Risk ratio:', ranked[0]['risk_ratio'])
    else:
        print('Best rule: No eligible rule')


if __name__ == '__main__':
    main()
