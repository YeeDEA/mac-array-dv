# Verification Plan — 4×4 INT8 Output-Stationary MAC Array

> Written before the RTL, updated as features were closed. Spec: [spec.md](spec.md).
> Every feature maps to at least one of: directed test, constrained-random + coverage, or SVA.

## 1. DUT summary

- 4×4 output-stationary array, outer-product streaming: beat k carries column k of A and
  row k of B; each PE(i,j) does `acc += a[i]*b[j]`. K beats → C = A(4×K)×B(K×4).
- Accumulator: 32-bit (16-bit product + 16 guard) — exact for K ≤ 131 071 (≈ 2^17; derivation in [spec.md](spec.md)), tests bound K ≤ 64.
- valid/ready handshake on both sides; drain row-by-row; auto-clear at tile boundary.

## 2. Feature table (final)

| # | Feature | Verified by | Coverage | Assertion | Status |
|---|---------|-------------|----------|-----------|--------|
| F1 | Signed INT8 multiply correctness (incl. −128×−128) | mac_pe_tb 36 sign/boundary corners + scoreboard vs SV ref model + Python golden cross-check | `cp_a`/`cp_b` value bins {min,neg,zero,pos,max}, cross `x_ab` | — | **verified** |
| F2 | Accumulation over K beats | 1000-random PE runs; 50-tile golden-vector TB; 20-seed × 20-tile CR regression | `cp_k` bins {1, 2–4, 5–8, 9–16} | — | **verified** |
| F3 | Accumulator width sufficiency (no wrap in-spec) | Directed max-magnitude streams: K=64 × (−128×127) in vector TB; K=16 corners in `mac_corner_seq` | corner-weighted dist hits ±extremes | guard math in spec.md | **verified** |
| F4 | acc changes only on accepted beat / clear, and every accepted beat is accumulated | random interleaved gaps in all TBs | — | A5 `a_acc_stable_when_idle` (no phantom update, interface-qualified), A6 `a_en_iff_accept` (no dropped beat), A11 | **verified** |
| F5 | Handshake protocol | random input gaps + drain backpressure in driver & unit TB | stall scenarios exercised every run | A1 `a_drain_blocks_in` (4 rows owed per tile, no input meanwhile), A12 `a_no_orphan_row`, A2 `a_out_stable`, A3 `a_row_inc`, A8 `a_in_stable` | **verified** |
| F6 | Reset behavior (power-on **and** mid-tile) | power-on reset every sim; `mac_reset_test` fires 4 reset pulses per run from precise protocol points — mid-ACCEPT after 1 and 3 beats, mid-DRAIN after rows 1 and 2 — each followed by ≥ 2 clean tiles checked by the scoreboard | reset test errors unless all 4 pulses fire and the monitor discards exactly 4 partial tiles | A9 `a_reset_clear` (acc **+ FSM state + row**), A10 `a_reset_quiet` | **verified** |
| F7 | Tile-boundary auto-clear, back-to-back tiles | 50 consecutive tiles (vector TB), 20-tile CR sequences | tile bins | A7 `a_tile_clear` (caught BUG3 — see M1 evidence) | **verified** |
| F8 | Boundary matrices (0 / ±max / identity / same-value / K=1) | `mac_corner_seq` 6 directed tiles + directed vector cases | value bins hit all extremes | — | **verified** |
| F9 | Drain row indexing / out_last | every drain checked in TB + scoreboard row assembly | — | A3, A4 `a_out_last_iff_row3` | **verified** |

## 3. Checking strategy (as built — three independent layers)

1. **SVA** (12 assertions, bound into the DUT, see internal `en/clr/acc`): protocol, state,
   reset, and — since the audit (E3) — one datapath check, A11 `a_acc_update`, which recomputes
   the expected accumulator from registered operands using the spec's arithmetic.
2. **UVM scoreboard**: SV reference model recomputes C from *monitored* input beats (64-bit
   exact, truncated to 32 to mirror wrap-exact hardware).
3. **Python golden model** (`regress/golden_model.py`): post-sim cross-check of the monitor's
   transaction dump, plus the 50-case pre-generated vector suite for the unit TB.

## 4. Coverage model (as built)

- SV covergroups (native xsim): `cg_vals` (5×5 value bins + cross), `cg_tile` (K bins:
  1, 2–4, 5–8, 9–16, 17–63, 64, plus a `default` bin so out-of-model K cannot hide).
- Python coverage (fallback A, runs every regression): 25 bins — value bins ×2 operands,
  3×3 sign cross, 6 K-bins — aggregated across the whole sweep.
- K reaches 64 both by constrained-random `dist` weighting and by two directed worst-case
  tiles in `mac_corner_seq` (−128×127 and −128×−128 for 64 beats), so the accumulator-width
  argument in spec.md is exercised rather than asserted (audit finding: it previously was not).

## 5. Exit criteria — status

- [x] M0: arbitrary 4×4 signed matmul exact vs golden model (50 tiles)
- [x] M1: assertion catches injected bug with evidence (docs/coverage_report/m1_sva_violation.txt)
- [x] M2: 20-seed unattended regression clean — 22/22 runs, coverage 100%
      (extended sweep: 50 seeds → **52/52 runs, ~1000 tiles, 0 mismatches**; after E5/E6 with
      5 reset seeds added → **57/57 runs, 1099 tiles, 0 mismatches, 25/25 Python bins**)
- [x] Functional coverage ≥ 90% target → measured 100% (both SV covergroups and Python bins)
- [x] M3: injected-bug hunt ≥ 4/5 caught → **5/5 caught** (docs/bug_log.md)

## 6. Audit of this environment — what it was NOT checking

An adversarial audit of the environment itself (not the DUT) found real defects in the checking.
They are listed here rather than quietly fixed, because "the testbench passed" is not the claim —
"the testbench can fail for the right reasons" is.

| # | Defect | Status |
|---|--------|--------|
| E1 | **A8 (`a_in_stable`) was 100% vacuous.** Both drivers asserted `in_valid` only at a negedge where `in_ready` was already high, so `in_valid && !in_ready` never occurred in any of the 52 runs. The input-side stall was structurally unreachable. | **fixed** — driver split into independent input/drain threads with valid-first handshake, so the next tile's first beat now stalls against the previous tile's drain. The monitor counts stall cycles and **errors the test if the count is zero**, so the vacuity cannot silently return. |
| E2 | **`in_ready`/`out_valid` were not reset-qualified.** They were pure combinational decodes of `state`, so during reset the DUT advertised `in_ready = 1` and a producer released one cycle early would see a phantom accept. | **fixed** — `rst_n &&` added in `ctrl.sv`, plus assertion A10 `a_reset_quiet`. |
| E3 | **No datapath assertion.** Every assertion checked protocol/state; none checked the accumulated *value*. That is why BUG1 (16-bit wrap) and BUG4 (sign) were caught only by the scoreboard — SVA was structurally blind, not merely unlucky. | **fixed** — assertion A11 `a_acc_update` recomputes the expected accumulator from registered operands. |
| E4 | **Scoreboard is X-blind.** `int'(c_row[...])` converts X to 0, so an undelivered drain row matches an expected value of 0. | **fixed** — explicit `$isunknown` check per lane. |
| E5 | **Reset was asserted once at time 0 and never again.** Mid-tile and mid-drain reset were unverified; A9/A10 only ever evaluated from the power-on state, and A9 checked the accumulators only. | **fixed** — `tb_uvm/rst_if.sv` lets a test pulse `rst_n`; `mac_reset_test` fires mid-ACCEPT (after 1, 3 beats) and mid-DRAIN (after rows 1, 2) resets. The driver kills both threads on reset, returns the in-flight item and re-initialises its outputs; the monitor discards the partial tile. A9 now also checks `state == ACCEPT && row == 0` via the bind. No DUT bug was found by these scenarios. |
| E6 | **A1, A5, A6 were weak.** A6 restated the RTL expression that defines `en` (a tautology); A1 restated a one-bit FSM encoding; A5 was qualified by the DUT's own `en`/`clr`, so any bug that raised `en` wrongly made it vacuous. | **fixed** — rewritten against intent, from interface handshakes only (see §6.1). Each rewrite is proven by an injected bug that trips it; for two of them the old form was measured to miss that bug. |
| E7 | **`ACC_W` is an inert parameter** — the `c_row` mux, the product width and the SVA bind hardcode 32/16. Overriding it would produce wrong results silently. | **open** — either propagate it or delete the parameter. |

### 6.1 E6 — rewritten assertions and the bugs that prove them

| Assertion | Old form | New form (intent) | Proof bug | Old form on that bug (measured) | New form (measured, `regress/bug_hunt.py`) |
|---|---|---|---|---|---|
| A1 `a_drain_blocks_in` | `out_valid \|-> !in_ready` | an interface-derived counter owes 4 rows after the `in_last` beat; while rows are owed: no input handshake, `out_valid` high, `out_last` exactly on the 4th row. Plus A12 `a_no_orphan_row`: no row offered unless owed | BUG2 (`out_last` on row 2) | **silent** (only A4 fired) | fires @255 ns corner / @1015 ns random / @235 ns reset |
| A5 `a_acc_stable_when_idle` | `!en && !clr \|=> acc stable` | `!(in_valid && in_ready) && !(tile-end handshake) \|=> acc stable` | new BUG6 (`en = in_valid`, accumulates during a stall) | **silent** (old A6 and A2 fired) | fires @235 ns corner / @1005 ns random / @195 ns reset |
| A6 `a_en_iff_accept` | `en == (in_valid && in_ready)` | every beat handshaked on the interface is accumulated with the spec arithmetic (`acc == acc_q + a*b`, all 16 PEs) | new BUG7 (`en` masked on `in_last`, last beat dropped) | fired (it is a white-box copy of the same wire) | fires @585 ns corner / @975 ns random / @185 ns reset; A11 is silent on BUG7 because `en` is low |
| A9 `a_reset_clear` (E5) | `!rst_n \|=> acc == 0` | `… && state == ACCEPT && row == 0` | new BUG8 (drain row not reset) | not run; acc-only form cannot observe `row` | fires @15 ns in all three tests. **Functionally masked**: the FSM re-zeroes `row` on drain entry, so the scoreboard sees 0 errors — only the assertion sees it |

Side effect: the new A6 also fires on the value bugs BUG1/BUG4 (with A11), and the new A5
fires on BUG5. With BUG6–8 the hunt is **8/8 caught**; see [bug_log.md](bug_log.md).

### 6.2 Array parameterization (N × N)

`mac_array_4x4`, `ctrl`, `mac_if` and the SVA module take a parameter `N` (default 4, N ≥ 2;
the module name is kept for history). The UVM package and `tb_top` follow the `MAC_N` macro;
the monitor's dump carries N (`TILE K N`) so the Python cross-check needs no flag.
Measured at N = 8: `MAC_N=8 python regress/run_regress.py --seeds 20` → **27/27 PASS,
499 tiles, 0 mismatches, 25/25 Python bins**, and BUG2 / BUG3 / BUG7 are still caught by
A1+A4 / A7 / A6 respectively. BUG3 is hard-wired to PE(2,3) and needs N ≥ 4.
The N = 4 sweep was rerun after the change: 57/57 PASS, unchanged.

## 7. Simulator limitations found (xsim 2020.2)

| Limitation | Workaround |
|---|---|
| `default disable iff` unsupported | per-property `disable iff (!rst_n)` |
| `$past`/`$stable` unsupported in properties | hand-rolled previous-cycle sample registers in the SVA module |
| `-testplusarg` needs quoting on Windows | wrapped in run scripts |
| `xvlog -d NAME=VALUE` is mangled (xvlog is a `.bat`; cmd splits on `=`) | pass defines through an option file (`-f defines.f`) |
| UVM lib has no timescale | `xelab -timescale 1ns/1ps` |
