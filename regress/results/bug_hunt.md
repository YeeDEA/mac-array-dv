# Injected-bug hunt results (W16)

## BUG1 — CAUGHT

mac_pe.sv — accumulator wraps at 16 bits (overflow guard removed)

- `mac_corner_test`: SVA a_en_iff_accept @355 ns, a_acc_update @355 ns; scoreboard (tile 2, C[0][0] got -4080 exp 258064); python golden cross-check (4/7 tiles bad)
- `mac_random_test`: SVA a_en_iff_accept @255 ns, a_acc_update @255 ns; scoreboard (tile 1, C[1][0] got 21201 exp -44335); python golden cross-check (20/20 tiles bad)
- `mac_reset_test`: SVA a_en_iff_accept @395 ns, a_acc_update @395 ns; scoreboard (tile 2, C[0][0] got -24670 exp 40866); python golden cross-check (15/18 tiles bad)

## BUG2 — CAUGHT

ctrl.sv — out_last at row 2 (off-by-one, tile drains 3 rows)

- `mac_corner_test`: SVA a_drain_blocks_in @255 ns, a_out_last_iff_row3 @255 ns; scoreboard; python golden cross-check (6/7 tiles bad)
- `mac_random_test`: SVA a_drain_blocks_in @1015 ns, a_out_last_iff_row3 @1015 ns; scoreboard; python golden cross-check (20/20 tiles bad)
- `mac_reset_test`: SVA a_drain_blocks_in @235 ns, a_out_last_iff_row3 @235 ns; scoreboard; python golden cross-check (18/18 tiles bad)

## BUG3 — CAUGHT

mac_array_4x4.sv — PE(2,3) clr gated off (never clears between tiles)

- `mac_corner_test`: SVA a_tile_clear @665 ns; scoreboard (tile 3, C[2][3] got 520208 exp 262144); python golden cross-check (5/7 tiles bad)
- `mac_random_test`: SVA a_tile_clear @1085 ns; scoreboard (tile 2, C[2][3] got -32695 exp -11742); python golden cross-check (19/20 tiles bad)
- `mac_reset_test`: SVA a_tile_clear @285 ns; scoreboard (tile 3, C[2][3] got 50933 exp 26812); python golden cross-check (13/18 tiles bad)

## BUG4 — CAUGHT

mac_pe.sv — b zero-extended (sign bug: b treated as unsigned)

- `mac_corner_test`: SVA a_en_iff_accept @675 ns, a_acc_update @675 ns; scoreboard (tile 3, C[0][0] got -262144 exp 262144); python golden cross-check (3/7 tiles bad)
- `mac_random_test`: SVA a_en_iff_accept @75 ns, a_acc_update @75 ns; scoreboard (tile 1, C[0][0] got -138918 exp 19034); python golden cross-check (20/20 tiles bad)
- `mac_reset_test`: SVA a_en_iff_accept @105 ns, a_acc_update @105 ns; scoreboard (tile 1, C[0][0] got 6871 exp 471); python golden cross-check (18/18 tiles bad)

## BUG5 — CAUGHT

ctrl.sv — drain advances without out_ready (handshake violation)

- `mac_corner_test`: SVA a_out_stable @245 ns, a_drain_blocks_in @255 ns, a_acc_stable_when_idle @575 ns; scoreboard (tile 1, C[0][0] got 14112 exp 542512); watchdog timeout (DUT hung the protocol); python golden cross-check (1/1 tiles bad)
- `mac_random_test`: SVA a_out_stable @995 ns, a_drain_blocks_in @1005 ns, a_acc_stable_when_idle @1275 ns; scoreboard (tile 2, C[0][0] got -18443 exp -9755); watchdog timeout (DUT hung the protocol); python golden cross-check (7/7 tiles bad)
- `mac_reset_test`: SVA a_out_stable @195 ns, a_drain_blocks_in @215 ns, a_acc_stable_when_idle @225 ns; scoreboard (tile 1, C[0][0] got -9157 exp -182526); watchdog timeout (DUT hung the protocol); python golden cross-check (3/3 tiles bad)

## BUG6 — CAUGHT

ctrl.sv — en = in_valid (accumulates during a stall, ignoring in_ready)

- `mac_corner_test`: SVA a_acc_stable_when_idle @235 ns, a_out_stable @245 ns; scoreboard (tile 1, C[1][0] got 32258 exp 0); python golden cross-check (6/7 tiles bad)
- `mac_random_test`: SVA a_out_stable @1005 ns, a_acc_stable_when_idle @1005 ns; scoreboard (tile 1, C[1][0] got -46621 exp -44335); python golden cross-check (19/20 tiles bad)
- `mac_reset_test`: SVA a_acc_stable_when_idle @195 ns, a_out_stable @225 ns; scoreboard (tile 1, C[1][0] got 5598 exp -6882); python golden cross-check (17/18 tiles bad)

## BUG7 — CAUGHT

ctrl.sv — en masked on in_last (last beat of every tile dropped)

- `mac_corner_test`: SVA a_en_iff_accept @585 ns; scoreboard (tile 2, C[0][0] got 241935 exp 258064); python golden cross-check (6/7 tiles bad)
- `mac_random_test`: SVA a_en_iff_accept @975 ns; scoreboard (tile 1, C[1][0] got -44238 exp -44335); python golden cross-check (20/20 tiles bad)
- `mac_reset_test`: SVA a_en_iff_accept @185 ns; scoreboard (tile 1, C[0][0] got -1127 exp 471); python golden cross-check (18/18 tiles bad)

## BUG8 — CAUGHT

ctrl.sv — drain row counter not reset (survives a mid-drain reset)

- `mac_corner_test`: SVA a_reset_clear @15 ns
- `mac_random_test`: SVA a_reset_clear @15 ns
- `mac_reset_test`: SVA a_reset_clear @15 ns

