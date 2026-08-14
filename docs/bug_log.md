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

## Injected-bug hunt (W16) — 5/5 caught

Each bug is a compile-time define (`xvlog -d BUGn`), hunted by `regress/bug_hunt.py` running
`mac_corner_test` + `mac_random_test` against the unmodified environment.

| Bug | Injection | SVA | Scoreboard | Python | Watchdog |
|-----|-----------|-----|------------|--------|----------|
| BUG1 | accumulator wraps at 16 bits | **A11 @265 ns** | tile 1 | 20/20 tiles | — |
| BUG2 | `out_last` at row 2 (off-by-one) | **A4 @235 ns** | ✓ | 20/20 tiles | ✓ |
| BUG3 | PE(2,3) `clr` gated off | **A7 @715 ns** | tile 2 | 19/20 tiles | — |
| BUG4 | `b` zero-extended (sign bug) | **A11 @95 ns** | tile 1 | 20/20 tiles | — |
| BUG5 | drain ignores `out_ready` | **A2 @195 ns** | ✓ | ✓ | ✓ |

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
