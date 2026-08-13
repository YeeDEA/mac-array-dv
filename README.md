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

- [x] W1 — repo bootstrap, verification plan skeleton, SystemVerilog toy compile on xsim
- [ ] W2 — `mac_pe.sv` (signed INT8, guarded accumulator) + directed self-checking TB
- [ ] W3 — 4×4 array + load-control FSM, matches Python golden model (**M0**)
- [ ] Phase 1 — valid/ready interface + SVA (**M1**: assertion-violation waveform)
- [ ] Phase 2 — UVM env: driver/monitor/scoreboard, constrained-random (**M2**: 20-seed regression)
- [ ] Phase 3 — functional coverage + regression + bug hunt (**M3**)
- [ ] Phase 4 — docs, results, final verification plan

## Results

*(to be filled with measured numbers — coverage %, seed counts, bugs found)*
