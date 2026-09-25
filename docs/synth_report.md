# Synthesis report — generic Yosys gate counts

Reproduce: `pip install yowasp-yosys` then `python synth/run_synth.py`
(logs in `synth/out/*.log`, table in `synth/out/summary.md`).

## What was actually run — and what was not

- Tool: **Yosys 0.69** (YoWASP WebAssembly build, `yowasp-yosys` from pip), on Windows.
- Flow per target: `read_verilog -sv …; synth -top <T> -flatten -noabc; stat -tech cmos`.
- **No ABC, no liberty.** In this YoWASP build the ABC pass exits silently (the process
  returns 0 with the log cut off inside `Executing ABC`); older YoWASP 0.40/0.50 wheels behave
  the same way here. So the netlist is Yosys's own techmapped generic gates
  (`$_AND_/$_OR_/$_XOR_/$_MUX_/$_NOT_` + flops) without ABC logic optimisation, and no
  standard-cell library was mapped. **These are not area numbers.** They are structural
  counts that are useful for *relative* comparison (multiplier vs adder vs register) and
  will overstate a real optimised netlist.
- "Est. transistors" is Yosys's `stat -tech cmos` estimate for the logic cells only
  (it prints `+` when flops are present because it does not cost them).

## Results

| target | what | logic cells | AND | OR | XOR | MUX | NOT | flops | est. transistors (logic only) |
|---|---|---|---|---|---|---|---|---|---|
| `pe_mul` | 8x8 signed multiplier (a*b) | 456 | 222 | 70 | 156 | 0 | 8 | 0 | 3640 |
| `pe_add` | 32b + sign-extended 16b adder | 220 | 105 | 52 | 63 | 0 | 0 | 0 | 1698 |
| `pe_reg` | 32b accumulator register w/ rst/clr/en | 2 | 0 | 1 | 0 | 0 | 1 | 32 | 8+ |
| `mac_pe` | one PE (all of the above) | 960 | 431 | 182 | 338 | 0 | 9 | 32 | 7752+ |
| `ctrl` | tile FSM | 21 | 9 | 4 | 1 | 3 | 4 | 3 | 134+ |
| `mac_array_4x4` | full 4x4 array (16 PE + ctrl + c_row mux) | 16242 | 7385 | 3260 | 5409 | 131 | 40 | 515 | 130430+ |
| `mac_array_4x4` | 8x8 build (64 PE), chparam N=8 | 65015 | 29610 | 13369 | 21634 | 260 | 77 | 2052 | 520756+ |

`pe_mul`/`pe_add`/`pe_reg` are in `synth/pe_parts.sv`: each is one expression of
`rtl/mac_pe.sv` synthesized alone so the PE can be split by function.

## Reading it

- **Flops: 515 = 16 × 32 accumulator bits + 3 control bits** (1 FSM state + 2 drain row),
  exactly what the RTL declares. The `rst/clr/en` priority costs almost nothing in logic
  (2 cells) because Yosys maps it onto sync-reset/enable flops (`$_SDFFE_*`).
- **The multiplier dominates the PE's combinational logic.** Synthesized separately, the
  8×8 signed multiplier is 456 cells / 3640 est. transistors vs 220 / 1698 for the 32-bit
  accumulate adder — about **2.1×**, i.e. ~67% of the PE's arithmetic. This matches the
  expectation in [cmos_background.md §4](cmos_background.md): 64 partial-product ANDs plus
  a compression tree of full adders, versus one carry chain.
  The XOR count points the same way: 156 XORs in the multiplier (full-adder sums in the
  partial-product tree) vs 63 in the adder.
- **Fused PE is larger than the sum of its parts** (960 vs 456 + 220 + 2 = 678 logic cells).
  In `mac_pe` Yosys merges `acc + a*b` into one `$macc` cell and lowers it with its own
  multiply-accumulate mapper; without ABC to clean up afterwards, that lowering is less
  compact than the two separate operators. With ABC (or a real synthesis tool) this gap is
  expected to shrink or invert — not measured here, so no number is claimed.
- **N = 8 scales as expected.** With the array parameterized (`chparam -set N 8`), flops are
  2052 = 64 × 32 + 1 state + 3 row bits, and logic is 65015 cells ≈ 64 × 960 (61440) + an
  8:1 read-out mux over 256 bits — ~4.0× the 4×4 build, i.e. quadratic in N, as the PE
  count is.
- **Array ≈ 16 × PE.** 16 × 960 = 15360 of the 16242 logic cells; the rest is the 4:1
  `c_row` read-out mux (131 `$_MUX_` + glue) and the 21-cell FSM. Control is ~0.1% of logic.

## Not done

- Liberty-mapped area (e.g. with an open PDK library such as SKY130 or NanGate45) — needs a
  working ABC; the next step is to rerun this script with a native `yosys` binary
  (Linux/WSL/CI), which picks it up automatically, and add `dfflibmap`/`abc -liberty`.
- Timing (no STA was run).
