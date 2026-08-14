"""Seed-swept regression driver for the mac_array_4x4 UVM environment.

Per seed: run mac_random_test on xsim, parse UVM error counts, then independently
cross-check the monitor's transaction dump against the Python golden model and
accumulate functional-coverage bins in Python (fallback A of the verification plan,
run alongside the native SV covergroups).

Usage:  python regress\\run_regress.py --seeds 20 [--ntiles 20] [--no-compile]
Failing seeds get a ready-to-paste repro command in the summary.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from golden_model import matmul, wrap32  # noqa: E402

VIVADO = os.environ.get("VIVADO_SETTINGS", r"C:\Xilinx\Vivado\2020.2\settings64.bat")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TB = os.path.join(ROOT, "tb_uvm")

RTL = r"..\rtl\mac_pe.sv ..\rtl\ctrl.sv ..\rtl\mac_array_4x4.sv ..\rtl\mac_if.sv"
SVA = r"..\sva\mac_array_sva.sv ..\sva\mac_bind.sv"


def shell(cmdline):
    """Run a command under the Vivado environment. xsim emits bytes that the Windows
    ANSI codepage cannot decode, so decode as UTF-8 with replacement rather than
    letting the reader thread die and hand back None."""
    full = f'call {VIVADO} && cd /d {TB} && {cmdline}'
    p = subprocess.run(["cmd", "/c", full], capture_output=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def compile_env(defines=""):
    rc, out = shell(f"xvlog -sv -L uvm {defines} {RTL} {SVA} mac_pkg.sv tb_top.sv "
                    f"&& xelab tb_top -L uvm -timescale 1ns/1ps -s uvm_sim")
    if rc != 0:
        print(out[-3000:])
        sys.exit("compile failed")


def run_test(test, seed, ntiles=None):
    plus = f' -testplusarg "NTILES={ntiles}"' if ntiles else ""
    rc, out = shell(f'xsim uvm_sim -runall -sv_seed {seed} '
                    f'-testplusarg "UVM_TESTNAME={test}"{plus}')
    errs = fatals = -1
    m = re.search(r"UVM_ERROR :\s+(\d+)", out)
    if m:
        errs = int(m.group(1))
    m = re.search(r"UVM_FATAL :\s+(\d+)", out)
    if m:
        fatals = int(m.group(1))
    sb_pass = "SCOREBOARD PASS" in out
    sva_err = "Assertion failed" in out
    cov = re.search(r"functional coverage: (values=[\d.]+% tile=[\d.]+%)", out)
    ok = (rc == 0) and (errs == 0) and (fatals == 0) and sb_pass and not sva_err
    return ok, errs, fatals, sva_err, (cov.group(1) if cov else "n/a")


# ---------------- Python-side golden cross-check + coverage (from txn_dump.log)
def lanes(hex32):
    x = int(hex32, 16)
    out = []
    for i in range(4):
        v = (x >> (8 * i)) & 0xFF
        out.append(v - 256 if v >= 128 else v)
    return out


def sign_cat(v):
    return "neg" if v < 0 else ("zero" if v == 0 else "pos")


class Coverage:
    VAL_BINS = ["min", "neg", "zero", "pos", "max"]
    K_BINS = ["k1", "k2_4", "k5_8", "k9_16", "k17_32", "k33_64"]

    def __init__(self):
        self.hits = {f"a_{b}": 0 for b in self.VAL_BINS}
        self.hits.update({f"b_{b}": 0 for b in self.VAL_BINS})
        self.hits.update({f"x_{sa}_{sb}": 0 for sa in ("neg", "zero", "pos") for sb in ("neg", "zero", "pos")})
        self.hits.update({k: 0 for k in self.K_BINS})

    @staticmethod
    def val_bin(v):
        if v == -128: return "min"
        if v == 127: return "max"
        if v == 0: return "zero"
        return "neg" if v < 0 else "pos"

    def sample(self, a, b):
        self.hits[f"a_{self.val_bin(a)}"] += 1
        self.hits[f"b_{self.val_bin(b)}"] += 1
        self.hits[f"x_{sign_cat(a)}_{sign_cat(b)}"] += 1

    def sample_k(self, k):
        key = ("k1" if k == 1 else "k2_4" if k <= 4 else "k5_8" if k <= 8
               else "k9_16" if k <= 16 else "k17_32" if k <= 32 else "k33_64")
        self.hits[key] += 1

    def pct(self):
        return 100.0 * sum(1 for v in self.hits.values() if v > 0) / len(self.hits)


def cross_check(dump_path, cov):
    """Recompute every tile with the golden model; return (n_tiles, n_bad)."""
    tiles = bad = 0
    with open(dump_path) as fh:
        lines = [l.strip() for l in fh if l.strip()]
    i = 0
    while i < len(lines):
        assert lines[i].startswith("TILE")
        K = int(lines[i].split()[1])
        cov.sample_k(K)
        A = [[0] * K for _ in range(4)]
        B = [[0] * 4 for _ in range(K)]
        for k in range(K):
            _, ah, bh = lines[i + 1 + k].split()
            al, bl = lanes(ah), lanes(bh)
            for x in range(4):
                A[x][k] = al[x]
                B[k][x] = bl[x]
                cov.sample(al[x], bl[x])
        obs = [list(map(int, lines[i + 1 + K + r].split()[1:])) for r in range(4)]
        exp = matmul(A, B, K)
        if obs != exp:
            bad += 1
        tiles += 1
        i += 1 + K + 4
    return tiles, bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--ntiles", type=int, default=20)
    ap.add_argument("--no-compile", action="store_true")
    args = ap.parse_args()

    os.makedirs(os.path.join(ROOT, "regress", "results"), exist_ok=True)
    if not args.no_compile:
        print("compiling...")
        compile_env()

    cov = Coverage()
    rows, fails = [], []

    for name, test, seed in [("smoke", "mac_smoke_test", 1), ("corner", "mac_corner_test", 1)]:
        ok, errs, fatals, sva, c = run_test(test, seed)
        t, b = cross_check(os.path.join(TB, "txn_dump.log"), cov)
        ok = ok and b == 0
        rows.append((name, seed, ok, errs, sva, c, t, b))
        if not ok:
            fails.append((test, seed))
        print(f"{name:8s} seed={seed:<4d} {'PASS' if ok else 'FAIL'}  sv_cov[{c}] xcheck {t} tiles {b} bad")

    for seed in range(1, args.seeds + 1):
        ok, errs, fatals, sva, c = run_test("mac_random_test", seed, args.ntiles)
        t, b = cross_check(os.path.join(TB, "txn_dump.log"), cov)
        ok = ok and b == 0
        rows.append(("random", seed, ok, errs, sva, c, t, b))
        if not ok:
            fails.append(("mac_random_test", seed))
        print(f"random   seed={seed:<4d} {'PASS' if ok else 'FAIL'}  sv_cov[{c}] xcheck {t} tiles {b} bad")

    total = len(rows)
    npass = sum(1 for r in rows if r[2])
    with open(os.path.join(ROOT, "regress", "results", "summary.md"), "w") as fh:
        fh.write(f"# Regression summary\n\n**{npass}/{total} runs PASS** · "
                 f"Python functional coverage (fallback A): **{cov.pct():.1f}%** "
                 f"({sum(1 for v in cov.hits.values() if v > 0)}/{len(cov.hits)} bins)\n\n")
        fh.write("| test | seed | result | UVM_ERROR | SVA viol | SV covergroups | tiles xchecked | xcheck bad |\n")
        fh.write("|---|---|---|---|---|---|---|---|\n")
        for n, s, ok, e, sva, c, t, b in rows:
            fh.write(f"| {n} | {s} | {'PASS' if ok else '**FAIL**'} | {e} | {sva} | {c} | {t} | {b} |\n")
        fh.write("\n## Coverage bins (Python, from monitor dump)\n\n")
        for k, v in cov.hits.items():
            fh.write(f"- `{k}`: {v}\n")
        if fails:
            fh.write("\n## Failing-seed repro commands\n\n```\ncd tb_uvm\n")
            for test, seed in fails:
                fh.write(f'xsim uvm_sim -runall -sv_seed {seed} -testplusarg "UVM_TESTNAME={test}"\n')
            fh.write("```\n")
    print(f"\n{npass}/{total} PASS · python coverage {cov.pct():.1f}% -> regress/results/summary.md")
    sys.exit(0 if npass == total else 1)


if __name__ == "__main__":
    main()
