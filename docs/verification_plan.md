# Verification Plan — 4×4 INT8 Output-Stationary MAC Array

> ★ This document is written **before** the RTL. Features first, design second.
> Every feature must map to at least one of: directed test, constrained-random + covergroup, or SVA.

## 1. DUT summary (spec, not implementation)

- 4×4 array of PEs, output-stationary: each PE holds `acc`, receives streamed `a` (INT8 signed) and `b` (INT8 signed), performs `acc += a*b`.
- Accumulator width: 16 + guard bits (exact guard count decided in W2, justified in this doc).
- Simple valid/ready-style load/drain interface (defined in Phase 1, W4).
- Synchronous reset; `clear` to zero accumulators between tiles.

## 2. Feature table

| # | Feature | How verified? | Covergroup? | Assertion (SVA)? | Status |
|---|---------|---------------|-------------|------------------|--------|
| F1 | Signed INT8 multiply correctness (incl. −128×−128) | Directed corner + random vs Python golden model (scoreboard) | input value bins: {−128, −1, 0, +1, +127}, sign cross | – | planned |
| F2 | Accumulation correctness over N cycles | Random streams, scoreboard vs golden model | stream length bins (1, 2, K, max) | – | planned |
| F3 | Accumulator overflow guard (no silent wrap) | Directed max-magnitude streams; check guard bits | overflow-approach bin | acc never wraps unnoticed / saturation flag behavior | planned |
| F4 | `acc` unchanged while weights/inputs are loading (no compute enable) | Random interleaved load/compute | – | `load_en |-> $stable(acc)` style | planned |
| F5 | Handshake protocol: no data transfer without valid&ready; data stable while valid & !ready | Random backpressure sequences | backpressure scenario bins | 3–5 protocol assertions | planned |
| F6 | Reset behavior: all `acc`=0, FSM to IDLE after reset | Directed reset-mid-operation test | – | post-reset state assertion | planned |
| F7 | `clear` between tiles zeroes accumulators, doesn't corrupt next tile | Back-to-back tile random test | tile-boundary cross | clear ⇒ acc==0 next cycle | planned |
| F8 | Boundary values: all-zero matrix, all-max, all-min, identity | Directed corner tests | value bins hit these | – | planned |

*(rows will grow as the interface is pinned down in W4–W5)*

## 3. Coverage model (draft)

- **cg_input_values**: bins on `a`/`b` — min, max, zero, ±1, mid-range buckets; cross `sign(a) × sign(b)`.
- **cg_stream**: accumulation length bins; back-to-back tiles; clear-timing.
- **cg_handshake**: valid-without-ready stall lengths {0, 1, 2–5, long}.
- Cross candidates (pick 1–2): value-corner × stream-length, backpressure × clear.

## 4. Checking strategy

- **Scoreboard**: Python golden model (numpy int64 accumulate) — file-based exchange first, DPI if time allows.
- **SVA**: protocol + data-integrity assertions listed above, bound in `sva/`.
- **Regression**: seed-swept via Python driver; failing seed → auto-printed repro command.

## 5. Exit criteria

- Functional coverage ≥ [X]% (target set after W13 first measurement).
- 20-seed regression clean (M2), all assertions enabled.
- Injected-bug hunt: environment catches ≥ 4/5 injected bugs (W16).
