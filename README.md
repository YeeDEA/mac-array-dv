# mac-array-dv

A 4×4 INT8 output-stationary MAC array in SystemVerilog, verified with a from-scratch UVM 1.2 environment — constrained-random stimulus, reference-model scoreboard, SVA, functional coverage, and Python-driven regression.

## Motivation

This project grew out of a computer architecture course where I implemented a 5-stage pipelined MIPS processor. What hooked me wasn't the design itself, but the quantitative side: measuring how hazards change execution time across instruction streams, and how cache configurations shift hit/miss behavior. I wanted to keep going in that direction, but as an exchange-bound student I couldn't commit to a multi-semester lab internship. After consulting with over ten professors on what a single semester could realistically produce, the consistent advice was: build one complete, self-contained artifact.

So the design (DUT) is deliberately small — the point is the verification infrastructure on top of it. Roughly 60% of the effort goes into the UVM environment: verification planning, constrained-random sequences, a scoreboard against a Python golden model, assertions, coverage closure, and seed-swept regression. Design verification is, at its core, the same thing I enjoyed in that course — quantitatively confirming how a system behaves.

## Repository layout

```
mac-array-dv/
├── rtl/           # mac_pe.sv, mac_array_4x4.sv, ctrl.sv  (~500 lines total)
├── tb_uvm/        # agent, driver, monitor, scoreboard, sequences, env, test
├── sva/           # protocol / data-integrity assertions
├── regress/       # Python regression scripts + seed management + summaries
├── docs/
│   ├── verification_plan.md   # feature → coverage → assertion mapping
│   ├── coverage_report/       # screenshots + numbers
│   └── bug_log.md             # bug reports (incl. injected-bug hunt)
└── README.md
```

## Toolchain

- Vivado 2020.2 `xsim` (UVM 1.2 built in — no extra installs), simulation only
- Python 3 for the golden model and regression driver

## Status

- [x] W1 — repo bootstrap, verification plan skeleton, SV toy + "Hello UVM" pass on xsim
- [x] W2 — `mac_pe.sv` + directed self-checking TB: 36 sign/boundary corners + 1000 randoms, 1073 checks PASS
- [x] W3 — 4×4 array + control FSM: 50 golden-model tiles PASS (**M0**)
- [x] Phase 1 — valid/ready protocol + **9 SVA** bound into the DUT; injected-bug assertion violation captured (**M1**, `docs/coverage_report/m1_sva_violation.txt`)
- [x] Phase 2 — UVM 1.2 env from scratch: agent (sequencer/driver/monitor), reference-model scoreboard, constrained-random with corner-weighted `dist`, smoke/random/corner tests (**M2**)
- [x] Phase 3 — functional coverage (native covergroups **and** Python bin-counting), 20-seed Python regression, injected-bug hunt (**M3**, `docs/bug_log.md`)
- [ ] Phase 4 — final packaging

## Results

| Metric | Value |
|---|---|
| Regression | **52/52 runs PASS** (smoke + corner + 50 random seeds × 20 tiles, ~1000 tiles) |
| Functional coverage | **100%** — SV covergroups (values, K-bins, sign cross) and 23/23 Python bins |
| Assertions | 9 SVA (protocol + data integrity), 0 violations on clean RTL |
| Golden-model cross-checks | 3 independent layers: SVA / SV scoreboard / Python post-sim recompute |
| Injected-bug hunt | **5/5 caught** — SVA first on 3 (protocol/state), scoreboard first on 2 (value-domain), each within the first tiles ([bug_log.md](docs/bug_log.md)) |
| Verification plan | 9 features → 3 covergroups → 9 assertions ([verification_plan.md](docs/verification_plan.md)) |

### Three-layer checking

```
constrained-random sequences ──> driver ──> DUT (4×4 MAC array) <── 9 SVA (bind, sees acc/en/clr)
                                              │
                                 monitor (posedge sampling)
                                   ├──> scoreboard: SV reference model (in-sim)
                                   ├──> covergroups: values × sign cross, K bins
                                   └──> txn dump ──> Python golden model cross-check + coverage bins (post-sim)
```

### xsim 2020.2 quirks discovered (documented in the verification plan)

`default disable iff` and `$past/$stable` unsupported in properties → per-property disable + hand-rolled sample registers; UVM lib needs `xelab -timescale`; `-testplusarg` quoting on Windows.
