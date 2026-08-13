# Verification Plan — 4×4 INT8 Output-Stationary MAC Array

> Written before the RTL, updated as features were closed. Spec: [spec.md](spec.md).
> Every feature maps to at least one of: directed test, constrained-random + coverage, or SVA.

## 1. DUT summary

- 4×4 output-stationary array, outer-product streaming: beat k carries column k of A and
  row k of B; each PE(i,j) does `acc += a[i]*b[j]`. K beats → C = A(4×K)×B(K×4).
- Accumulator: 32-bit (16-bit product + 16 guard) — exact for K ≤ 2^15, tests bound K ≤ 64.
- valid/ready handshake on both sides; drain row-by-row; auto-clear at tile boundary.

## 2. Feature table (final)

| # | Feature | Verified by | Coverage | Assertion | Status |
|---|---------|-------------|----------|-----------|--------|
| F1 | Signed INT8 multiply correctness (incl. −128×−128) | mac_pe_tb 36 sign/boundary corners + scoreboard vs SV ref model + Python golden cross-check | `cp_a`/`cp_b` value bins {min,neg,zero,pos,max}, cross `x_ab` | — | **verified** |
| F2 | Accumulation over K beats | 1000-random PE runs; 50-tile golden-vector TB; 20-seed × 20-tile CR regression | `cp_k` bins {1, 2–4, 5–8, 9–16} | — | **verified** |
| F3 | Accumulator width sufficiency (no wrap in-spec) | Directed max-magnitude streams: K=64 × (−128×127) in vector TB; K=16 corners in `mac_corner_seq` | corner-weighted dist hits ±extremes | guard math in spec.md | **verified** |
| F4 | acc changes only on accepted beat / clear | random interleaved gaps in all TBs | — | A5 `a_acc_stable_when_idle`, A6 `a_en_iff_accept` | **verified** |
| F5 | Handshake protocol | random input gaps + drain backpressure in driver & unit TB | stall scenarios exercised every run | A1 `a_drain_blocks_in`, A2 `a_out_stable`, A3 `a_row_inc`, A8 `a_in_stable` | **verified** |
| F6 | Reset behavior | reset applied before every sim; checked post-reset | — | A9 `a_reset_clear` | **verified** |
| F7 | Tile-boundary auto-clear, back-to-back tiles | 50 consecutive tiles (vector TB), 20-tile CR sequences | tile bins | A7 `a_tile_clear` (caught BUG3 — see M1 evidence) | **verified** |
| F8 | Boundary matrices (0 / ±max / identity / same-value / K=1) | `mac_corner_seq` 6 directed tiles + directed vector cases | value bins hit all extremes | — | **verified** |
| F9 | Drain row indexing / out_last | every drain checked in TB + scoreboard row assembly | — | A3, A4 `a_out_last_iff_row3` | **verified** |

## 3. Checking strategy (as built — three independent layers)

1. **SVA** (9 assertions, bound into the DUT, see internal `en/clr/acc`): protocol + integrity.
2. **UVM scoreboard**: SV reference model recomputes C from *monitored* input beats (64-bit
   exact, truncated to 32 to mirror wrap-exact hardware).
3. **Python golden model** (`regress/golden_model.py`): post-sim cross-check of the monitor's
   transaction dump, plus the 50-case pre-generated vector suite for the unit TB.

## 4. Coverage model (as built)

- SV covergroups (native xsim): `cg_vals` (5×5 value bins + cross), `cg_tile` (K bins) —
  100% values / 100% tile on the 20-seed regression.
- Python coverage (fallback A, runs every regression): 23 bins — value bins ×2 operands,
  3×3 sign cross, 4 K-bins — **100% (23/23)** on the 20-seed sweep.

## 5. Exit criteria — status

- [x] M0: arbitrary 4×4 signed matmul exact vs golden model (50 tiles)
- [x] M1: assertion catches injected bug with evidence (docs/coverage_report/m1_sva_violation.txt)
- [x] M2: 20-seed unattended regression clean — 22/22 runs, coverage 100%
- [x] Functional coverage ≥ 90% target → measured 100% (both SV covergroups and Python bins)
- [x] M3: injected-bug hunt ≥ 4/5 caught → **5/5 caught** (docs/bug_log.md)

## 6. Simulator limitations found (xsim 2020.2)

| Limitation | Workaround |
|---|---|
| `default disable iff` unsupported | per-property `disable iff (!rst_n)` |
| `$past`/`$stable` unsupported in properties | hand-rolled previous-cycle sample registers in the SVA module |
| `-testplusarg` needs quoting on Windows | wrapped in run scripts |
| UVM lib has no timescale | `xelab -timescale 1ns/1ps` |
