# Bug Log

Every entry: symptom → root cause → evidence → fix → re-verification.

## Real bugs found during bring-up

| # | Found by | Symptom | Root cause | Fix | Re-verified |
|---|----------|---------|------------|-----|-------------|
| R1 | xvlog | package failed to parse | covergroup bin named `small` — a reserved Verilog keyword (charge strength) | renamed `k_low/k_mid/k_high` | full regression |
| R2 | xelab | "module has timescale but at least one module doesn't" | Xilinx UVM library compiled without a timescale | `xelab -timescale 1ns/1ps` | full regression |
| R3 | xelab | `default disable iff` / `$past` / `$stable` rejected | xsim 2020.2 implements a subset of SVA | per-property `disable iff` + hand-rolled previous-cycle sample registers | 11 assertions active |
| R4 | regression driver crash | `TypeError: NoneType + str` mid-sweep | xsim emits bytes the Windows ANSI codepage can't decode; the subprocess reader thread died and `stdout` came back `None` | decode as UTF-8 with `errors="replace"` | 20-seed sweep |
| R5 | audit | `in_ready`/`out_valid` advertised during reset | pure combinational decode of `state`, not reset-qualified — a producer released one cycle early sees a phantom accept | `rst_n &&` in `ctrl.sv` + assertion A10 | full regression |

## Environment defects (the testbench was wrong, not the DUT)

See [verification_plan.md §6](verification_plan.md) for the full audit table. The headline:
**A8 `a_in_stable` passed vacuously in all 52 runs** — the driver only asserted `in_valid`
when `in_ready` was already high, so the stall it checks was structurally unreachable.
Fixed by splitting the driver into independent input/drain threads; the monitor now counts
stall cycles and **errors the test if the count is zero**, so the vacuity cannot return silently.

### K distribution ignored — stimulus looked random, but not with the intended weights

- **Symptom.** `c_k` asked for K (tile length) weighted 50 / 25 / 15 / 10 % over
  1–8 / 9–16 / 17–32 / 33–64. Across the 50-seed sweep the random test instead produced
  **10.6 / 13.2 / 26.5 / 49.7 %** (1000 tiles) — exactly the uniform-over-1..64 shares
  (12.5 / 12.5 / 25 / 50). Coverage was still **100 %**, because every K bin was hit; the
  bins say *whether* a value appeared, not *how often*.
- **Evidence.** Standalone xsim experiments (1000 draws each, Vivado 2020.2):

  | constraint on `k` | 1–8 | 9–16 | 17–32 | 33–64 |
  |---|---|---|---|---|
  | `dist` only | 52.4 | 24.8 | 13.2 | 9.6 |
  | `inside {[1:64]}` + `dist` (the original `c_k`) | 12.0 | 12.9 | 24.5 | 50.6 |
  | `dist` + inline `with {k <= 64;}` | 13.3 | 11.7 | 26.1 | 48.9 |

  Removing the redundant `inside` fixed the standalone case but **not** the real
  environment (still 10.6 / 13.2 / 26.5 / 49.7 %), so the solver's handling of `dist`
  could not be trusted here. The exact trigger inside the UVM item was not isolated.
- **Fix.** The weighting no longer depends on the constraint solver:
  `mac_random_seq::pick_k()` chooses the bucket with a procedural `randcase` and passes the
  value as `randomize() with { k_len == k; }`; `c_k` keeps only the legal range.
- **Guard.** `regress/run_regress.py` now reports the random-test K shares and **fails the
  regression** if any bucket is more than 7.5 points off target (≥ 200 tiles) — coverage alone
  cannot catch this class of bug.
- **Re-verify.** 57/57 PASS at N = 4, K shares **48.4 / 22.1 / 16.7 / 12.8 %** over 1000
  random tiles, coverage 25/25 bins.
- **Consequence for earlier numbers.** Before the fix, ~50 % of random tiles had K ≥ 33, so
  the pre-fix sweeps exercised long tiles far *more* than intended (long-K accumulator margin
  was over-tested, short-K handshake turnover under-tested). No earlier pass/fail result changes.

## Injected-bug hunt (W16, extended in E5/E6) — 8/8 caught

Each bug is a compile-time define (`xvlog -d BUGn`), hunted by `regress/bug_hunt.py` running
`mac_corner_test` + `mac_random_test` + `mac_reset_test` against the unmodified environment.
The table below is the first detection per layer on the random test (full per-test detail in
[regress/results/bug_hunt.md](../regress/results/bug_hunt.md)). BUG6–8 were added to prove the rewritten
assertions A5/A6/A9 (verification_plan §6.1).

| Bug | Injection | SVA (first, random test) | Scoreboard | Python | Watchdog |
|-----|-----------|-----|------------|--------|----------|
| BUG1 | accumulator wraps at 16 bits | **A6 + A11 @255 ns** | tile 1 | 20/20 tiles | — |
| BUG2 | `out_last` at row 2 (off-by-one) | **A1 + A4 @1015 ns** | ✓ | 20/20 tiles | — |
| BUG3 | PE(2,3) `clr` gated off | **A7 @1085 ns** | tile 2 | 19/20 tiles | — |
| BUG4 | `b` zero-extended (sign bug) | **A6 + A11 @75 ns** | tile 1 | 20/20 tiles | — |
| BUG5 | drain ignores `out_ready` | **A2 @995 ns**, A1, A5 | tile 2 | 7/7 tiles | ✓ |
| BUG6 | `en = in_valid` (accumulates during stall) | **A5 + A2 @1005 ns** | tile 1 | 19/20 tiles | — |
| BUG7 | `en` masked on `in_last` (last beat dropped) | **A6 @975 ns** | tile 1 | 20/20 tiles | — |
| BUG8 | drain row not reset | **A9 @15 ns** | — (functionally masked) | — | — |

Numbers are from the post-E6 run; the earlier 5-bug table differed only in which assertion
fired first (before E6, BUG2 was caught by A4 alone and BUG1/BUG4 by A11 alone).
BUG8 is the honest outlier: the FSM re-zeroes `row` when a drain starts, so the defect never
corrupts a result and only the extended A9 can see it. It is kept because a reset that leaves
state behind is a real class of silicon bug, even when this particular RTL hides it.

### What changed after the audit — and why it is the most interesting result

The **first** hunt (before the audit) looked like this:

| | SVA | Scoreboard |
|---|---|---|
| BUG1 (value) | **missed** | caught |
| BUG4 (value) | **missed** | caught |
| BUG5 (protocol) | caught | **missed** (UVM_ERROR = 0 — every value was correct) |

That was read as "each layer covers the other's blind spot", which was true but incomplete.
The real finding was that **SVA's blindness was structural, not accidental**: all nine assertions
checked protocol and state, and not one checked the accumulated *value*. Adding A11
`a_acc_update` — which recomputes the expected accumulator from registered operands using the
spec's arithmetic rather than the RTL's expression — closed it. SVA now catches 5/5, and catches
the two value bugs **hundreds of nanoseconds before** the scoreboard reaches the end of a tile.

The scoreboard is still not redundant: it is an independent implementation, so it is the check
that would survive A11 itself being wrong. Layered checking earns its keep by independence,
not by counting layers.
