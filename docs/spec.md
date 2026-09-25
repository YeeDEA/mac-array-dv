# DUT Spec — mac_array_4x4 (output-stationary, outer-product streaming)

## Dataflow
C(4×4) = A(4×K) × B(K×4), K ≥ 1 (streaming, no upper bound in HW; tests use K ≤ 64).
Beat k carries **column k of A** (`a_col`, 4 lanes) and **row k of B** (`b_row`, 4 lanes).
Each PE(i,j): `acc += a_col[i] * b_row[j]` — pure output-stationary, no weight loading phase.

## Accumulator width = 32 (16-bit product + 16 guard bits)
INT8×INT8 signed product ∈ [−16256, +16384], which fits signed 16 bits (range −32768..32767).
Summing N such products needs 16 + ⌈log₂N⌉ bits by the usual rule of thumb, which gives N ≤ 2¹⁶ beats
for 32 bits. The tight bound is larger, because the largest product magnitude is 2¹⁴, not 2¹⁵:
the accumulator is exact while N·16384 ≤ 2³¹ − 1, i.e. **N ≤ 131 071 beats (≈ 2¹⁷)**
(the negative side, N·16256 ≤ 2³¹, is looser). This single bound is the one used everywhere in the docs.
Tests bound K ≤ 64, so the margin is 2¹⁰×. No saturation logic: in-spec overflow is impossible,
and `mac_pe` therefore wraps rather than saturates if the bound is ever exceeded (BUG1 injects exactly that).

## Ports (mac_array_4x4, packed lanes: lane n = bits [8n+7:8n] / [32n+31:32n], signed)
| Port | Dir | Width | Meaning |
|---|---|---|---|
| clk, rst_n | in | 1 | sync active-low reset |
| in_valid / in_ready / in_last | in/out/in | 1 | input stream handshake; `in_last`=final beat of tile |
| a_col / b_row | in | 32 | 4 × INT8 lanes |
| out_valid / out_ready / out_last | out/in/out | 1 | drain handshake; `out_last`=row 3 |
| out_row | out | 2 | row index being drained |
| c_row | out | 128 | 4 × INT32 lanes = C[out_row][0..3] |

## Protocol rules (→ SVA)
1. Transfer occurs iff valid && ready at posedge.
2. During DRAIN, `in_ready`=0 (A1). 3. `c_row`/`out_row` stable while out_valid && !out_ready (A2).
4. `out_row` increments per accepted drain beat (A3); `out_last` ⇔ out_row==3 (A4).
5. acc changes only on accepted beat or clear (A5); en ⇔ accepted input beat (A6).
6. After out_last accepted, all acc==0 (auto-clear, A7). 7. Input stable during stall — env obligation (A8).
8. Reset → acc==0, state=ACCEPT (A9).

## FSM (ctrl.sv)
ACCEPT --(beat && in_last)--> DRAIN(row 0..3) --(row3 accepted, clr pulse)--> ACCEPT.

## Injected-bug hooks (W16, compile-time defines, default off)
BUG1 acc wraps at 16b (guard removal) · BUG2 out_last at row2 (off-by-one) · BUG3 PE(2,3) never clears · BUG4 b zero-extended (sign bug) · BUG5 drain ignores out_ready (handshake).
