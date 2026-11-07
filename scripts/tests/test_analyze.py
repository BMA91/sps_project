import pandas as pd

from scripts.analyze import rule_b, rule_c, rule_npi


def test_rule_npi_threshold():
    row = {'NPI': 5.41}
    assert rule_npi(row) is True
    row2 = {'NPI': 5.4}
    assert rule_npi(row2) is False


def test_rule_b_threshold():
    row = {'GRADE': 3, 'LYMPH_NODES_POSITIVE': 4}
    assert rule_b(row) is True
    row2 = {'GRADE': 3, 'LYMPH_NODES_POSITIVE': 3}
    assert rule_b(row2) is False


def test_rule_c_missing_values():
    row = {'AGE_AT_DIAGNOSIS': 60, 'TUMOR_SIZE_MM': 25, 'GRADE': 3, 'LYMPH_NODES_POSITIVE': 1}
    assert rule_c(row) is True
    row2 = {'AGE_AT_DIAGNOSIS': None, 'TUMOR_SIZE_MM': 25, 'GRADE': 3, 'LYMPH_NODES_POSITIVE': 1}
    assert rule_c(row2) is False


def test_sample_table_counts():
    df = pd.DataFrame([
        {'PATIENT_ID': 'p1', 'OUTCOME': 'died', 'AGE_AT_DIAGNOSIS': 60, 'TUMOR_SIZE_MM': 30, 'GRADE': 3, 'LYMPH_NODES_POSITIVE': 6, 'NPI': 7.1},
        {'PATIENT_ID': 'p2', 'OUTCOME': 'living', 'AGE_AT_DIAGNOSIS': 50, 'TUMOR_SIZE_MM': 15, 'GRADE': 2, 'LYMPH_NODES_POSITIVE': 0, 'NPI': 4.0},
        {'PATIENT_ID': 'p3', 'OUTCOME': 'living', 'AGE_AT_DIAGNOSIS': 70, 'TUMOR_SIZE_MM': 26, 'GRADE': 3, 'LYMPH_NODES_POSITIVE': 2, 'NPI': 5.5},
        {'PATIENT_ID': 'p4', 'OUTCOME': 'died', 'AGE_AT_DIAGNOSIS': 65, 'TUMOR_SIZE_MM': 28, 'GRADE': 3, 'LYMPH_NODES_POSITIVE': 5, 'NPI': 6.2},
    ])
    assert df['OUTCOME'].isin(['died', 'living']).all()
    assert len(df) == 4
    assert df[df['OUTCOME'] == 'died'].shape[0] == 2
