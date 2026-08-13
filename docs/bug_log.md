# Bug Log

Every entry: symptom → root cause → evidence → fix → re-verification.

## Real bugs found during bring-up

| # | Date | Found by | Symptom | Root cause | Fix | Re-verified |
|---|------|----------|---------|------------|-----|-------------|
| R1 | 08-13 | xvlog compile | package failed to parse | covergroup bin named `small` — a reserved Verilog keyword (charge strength) | renamed bins `k_low/k_mid/k_high` | full regression |
| R2 | 08-13 | xelab | "module has timescale but uvm_pkg doesn't" | Xilinx UVM lib compiled without timescale | `xelab -timescale 1ns/1ps` | full regression |
| R3 | 08-13 | xelab | `default disable iff` / `$past` / `$stable` rejected | xsim 2020.2 SVA subset | per-property disable + hand-rolled sample registers | 9 assertions active, M1 evidence |

## Injected-bug hunt (W16) — 5/5 caught

Each bug is a compile-time define (`xvlog -d BUGn`), hunted by `regress/bug_hunt.py`
running `mac_corner_test` + `mac_random_test` against the unmodified environment.
Detection layers: **SVA** (cycle-accurate, localizes mechanism) → **scoreboard** (SV
reference model, in-sim) → **Python golden cross-check** (post-sim) → **watchdog** (hangs).

| Bug | Injection | First detector | Evidence (from hunt log) |
|-----|-----------|----------------|--------------------------|
| BUG1 | `mac_pe.sv` — accumulator wraps at 16 bits (overflow guard removed) | **scoreboard** (SVA structurally blind to value-domain truncation) | corner: tile 2 C[0][0] got −4080 exp 258064; random: 16/20 tiles bad, UVM_ERROR=45 |
| BUG2 | `ctrl.sv` — `out_last` at row 2 (off-by-one, tile drains 3 rows) | **SVA `a_out_last_iff_row3`** at 155–235 ns, then scoreboard, then watchdog (driver starves waiting for row 3) | Assertion failed, mac_array_sva.sv:44 |
| BUG3 | `mac_array_4x4.sv` — PE(2,3) `clr` gated off (never clears between tiles) | **SVA `a_tile_clear`** at 215–705 ns (≈400 ns before the data check — see M1 evidence) | Assertion failed, mac_array_sva.sv:53; random: 19/20 tiles bad |
| BUG4 | `mac_pe.sv` — `b` zero-extended (sign bug, b treated as unsigned) | **scoreboard**, first tile with negative b | corner: C[0][0] got −262144 exp +262144 (sign flip); random: 20/20 tiles bad, UVM_ERROR=303 |
| BUG5 | `ctrl.sv` — drain advances without `out_ready` (handshake violation) | **SVA `a_out_stable`** at 105–215 ns; scoreboard sees nothing wrong (values correct!) — protocol-only bug, then watchdog | Assertion failed, mac_array_sva.sv:38, UVM_ERROR=0 |

### Lessons (interview material)

1. **Value-domain bugs (BUG1/BUG4) are invisible to protocol SVA** — only a reference
   model catches them. **Protocol bugs (BUG5) are invisible to the scoreboard** — data
   was numerically correct while the handshake was broken. Layered checking is not
   redundancy; each layer has a blind spot the other covers.
2. SVA localized BUG2/BUG3/BUG5 to the exact cycle and mechanism within ~200 ns;
   the end-to-end check reported them tiles later (or never, for BUG5).
3. A watchdog timeout is itself a detector: two bugs hung the protocol, and without
   `set_timeout` the regression would have stalled instead of failing.
