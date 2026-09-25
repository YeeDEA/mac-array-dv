# Regression summary (N = 8)

**27/27 runs PASS** · Python functional coverage (fallback A): **100.0%** (25/25 bins)

| test | seed | result | UVM_ERROR | SVA viol | SV covergroups | tiles xchecked | xcheck bad |
|---|---|---|---|---|---|---|---|
| smoke | 1 | PASS | 0 | False | values=69.3% tile=16.7% | 2 | 0 |
| corner | 1 | PASS | 0 | False | values=60.0% tile=66.7% | 7 | 0 |
| reset | 1 | PASS | 0 | False | values=100.0% tile=50.0% | 18 | 0 |
| reset | 2 | PASS | 0 | False | values=100.0% tile=50.0% | 18 | 0 |
| reset | 3 | PASS | 0 | False | values=100.0% tile=33.3% | 18 | 0 |
| reset | 4 | PASS | 0 | False | values=100.0% tile=50.0% | 18 | 0 |
| reset | 5 | PASS | 0 | False | values=100.0% tile=50.0% | 18 | 0 |
| random | 1 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 2 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 3 | PASS | 0 | False | values=100.0% tile=33.3% | 20 | 0 |
| random | 4 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 5 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 6 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 7 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 8 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 9 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 10 | PASS | 0 | False | values=100.0% tile=33.3% | 20 | 0 |
| random | 11 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 12 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 13 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 14 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 15 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 16 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 17 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 18 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 19 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |
| random | 20 | PASS | 0 | False | values=100.0% tile=50.0% | 20 | 0 |

## Coverage bins (Python, from monitor dump)

- `a_min`: 13299
- `a_neg`: 36184
- `a_zero`: 12226
- `a_pos`: 36314
- `a_max`: 12321
- `b_min`: 12686
- `b_neg`: 36323
- `b_zero`: 12126
- `b_pos`: 36351
- `b_max`: 12858
- `x_neg_neg`: 22059
- `x_neg_zero`: 5354
- `x_neg_pos`: 22070
- `x_zero_neg`: 5476
- `x_zero_zero`: 1399
- `x_zero_pos`: 5351
- `x_pos_neg`: 21474
- `x_pos_zero`: 5373
- `x_pos_pos`: 21788
- `k1`: 9
- `k2_4`: 28
- `k5_8`: 46
- `k9_16`: 114
- `k17_32`: 111
- `k33_64`: 191
