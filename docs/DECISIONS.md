# Project decision log

This log records the fixed decisions used throughout the analysis. These values are treated as constants once the team confirms them.

| Decision | Value |
|---|---|
| Group 1 ("died") | Patients who died of the disease |
| Group 2 ("survived") | Living patients |
| Excluded | Died of other causes; patients with missing age, size, grade, or nodes |
| Follow-up handling | Not applied; noted as a limitation in the report |
| Rule A | NPI above 5.4 |
| Rule B | Grade 3 AND 4 or more positive lymph nodes |
| Rule C | Age 60 or older AND size 25 mm or more AND grade 3 AND at least 1 positive node |
| `MIN_SIZE` | 10 |
| Significance threshold | 0.05 / number of rules (Bonferroni) |
| Statistical test | Fisher's exact test on the 2x2 table |
| README/report language | English |

NPI reference: `NPI = 0.2 x tumor size in cm + node stage + grade`, with node stage = 1 for 0 positive nodes, 2 for 1-3 positive nodes, and 3 for 4 or more positive nodes.
