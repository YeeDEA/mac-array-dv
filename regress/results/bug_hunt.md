# Injected-bug hunt results (W16)

## BUG1 — CAUGHT

mac_pe.sv — accumulator wraps at 16 bits (overflow guard removed)

- `mac_corner_test`: SVA (mac_array_sva.sv line 84, first at 335 ns); scoreboard (tile 2, C[0][0] got -4080 exp 258064); python golden cross-check (4/7 tiles bad)
- `mac_random_test`: SVA (mac_array_sva.sv line 84, first at 265 ns); scoreboard (tile 1, C[1][0] got 21201 exp -44335); python golden cross-check (20/20 tiles bad)

## BUG2 — CAUGHT

ctrl.sv — out_last at row 2 (off-by-one, tile drains 3 rows)

- `mac_corner_test`: SVA (mac_array_sva.sv line 61, first at 235 ns); scoreboard; python golden cross-check (6/7 tiles bad)
- `mac_random_test`: SVA (mac_array_sva.sv line 61, first at 1045 ns); scoreboard; python golden cross-check (20/20 tiles bad)

## BUG3 — CAUGHT

mac_array_4x4.sv — PE(2,3) clr gated off (never clears between tiles)

- `mac_corner_test`: SVA (mac_array_sva.sv line 70, first at 715 ns); scoreboard (tile 3, C[2][3] got 520208 exp 262144); python golden cross-check (5/7 tiles bad)
- `mac_random_test`: SVA (mac_array_sva.sv line 70, first at 1115 ns); scoreboard (tile 2, C[2][3] got -32695 exp -11742); python golden cross-check (19/20 tiles bad)

## BUG4 — CAUGHT

mac_pe.sv — b zero-extended (sign bug: b treated as unsigned)

- `mac_corner_test`: SVA (mac_array_sva.sv line 84, first at 725 ns); scoreboard (tile 3, C[0][0] got -262144 exp 262144); python golden cross-check (3/7 tiles bad)
- `mac_random_test`: SVA (mac_array_sva.sv line 84, first at 95 ns); scoreboard (tile 1, C[0][0] got -138918 exp 19034); python golden cross-check (20/20 tiles bad)

## BUG5 — CAUGHT

ctrl.sv — drain advances without out_ready (handshake violation)

- `mac_corner_test`: SVA (mac_array_sva.sv line 55, first at 195 ns); scoreboard (tile 1, C[0][0] got 262144 exp 520208); watchdog timeout (DUT hung the protocol); python golden cross-check (2/2 tiles bad)
- `mac_random_test`: SVA (mac_array_sva.sv line 55, first at 1005 ns); scoreboard (tile 1, C[0][0] got 72117 exp 90340); watchdog timeout (DUT hung the protocol); python golden cross-check (4/4 tiles bad)

