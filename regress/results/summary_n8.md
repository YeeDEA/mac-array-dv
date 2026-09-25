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
| random | 1 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 2 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 3 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 4 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 5 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 6 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 7 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 8 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 9 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 10 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 11 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 12 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 13 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 14 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 15 | PASS | 0 | False | values=100.0% tile=66.7% | 20 | 0 |
| random | 16 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 17 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 18 | PASS | 0 | False | values=100.0% tile=100.0% | 20 | 0 |
| random | 19 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |
| random | 20 | PASS | 0 | False | values=100.0% tile=83.3% | 20 | 0 |

## Coverage bins (Python, from monitor dump)

- `a_min`: 6966
- `a_neg`: 17203
- `a_zero`: 5827
- `a_pos`: 17300
- `a_max`: 5952
- `b_min`: 6438
- `b_neg`: 17271
- `b_zero`: 5803
- `b_pos`: 17347
- `b_max`: 6389
- `x_neg_neg`: 10910
- `x_neg_zero`: 2561
- `x_neg_pos`: 10698
- `x_zero_neg`: 2578
- `x_zero_zero`: 689
- `x_zero_pos`: 2560
- `x_pos_neg`: 10221
- `x_pos_zero`: 2553
- `x_pos_pos`: 10478
- `k1`: 22
- `k2_4`: 87
- `k5_8`: 117
- `k9_16`: 165
- `k17_32`: 73
- `k33_64`: 35
