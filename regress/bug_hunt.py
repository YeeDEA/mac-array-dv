"""W16 injected-bug hunt: compile the DUT with each BUGn define and record which
layer of the environment (SVA / scoreboard / Python cross-check / watchdog) catches it.

Usage: python regress\\bug_hunt.py            -> writes regress/results/bug_hunt.md
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_regress import shell, compile_env, TB, ROOT, Coverage, cross_check  # noqa: E402

BUGS = {
    "BUG1": "mac_pe.sv — accumulator wraps at 16 bits (overflow guard removed)",
    "BUG2": "ctrl.sv — out_last at row 2 (off-by-one, tile drains 3 rows)",
    "BUG3": "mac_array_4x4.sv — PE(2,3) clr gated off (never clears between tiles)",
    "BUG4": "mac_pe.sv — b zero-extended (sign bug: b treated as unsigned)",
    "BUG5": "ctrl.sv — drain advances without out_ready (handshake violation)",
}
TESTS = [("mac_corner_test", 1), ("mac_random_test", 2)]


def run_one(test, seed):
    rc, out = shell(f'xsim uvm_sim -runall -sv_seed {seed} -testplusarg "UVM_TESTNAME={test}"')
    det = []
    sva = re.findall(r"Assertion failed.*?\n.*?Line:(\d+)", out)
    if sva:
        det.append(f"SVA (mac_array_sva.sv line {sva[0]}, first at "
                   f"{re.search(r'Time: ([0-9]+ [a-z]+)', out).group(1) if re.search(r'Time: ([0-9]+ [a-z]+)', out) else '?'})")
    m = re.search(r"UVM_ERROR :\s+(\d+)", out)
    n_err = int(m.group(1)) if m else 0
    sb = re.search(r"\[SB\] tile (\d+) C\[(\d+)\]\[(\d+)\] got (-?\d+) expected (-?\d+)", out)
    if sb:
        det.append(f"scoreboard (tile {sb.group(1)}, C[{sb.group(2)}][{sb.group(3)}] "
                   f"got {sb.group(4)} exp {sb.group(5)})")
    elif n_err > 0 and "SCOREBOARD FAIL" in out:
        det.append("scoreboard")
    if "PH_TIMEOUT" in out or "timeout" in out.lower():
        det.append("watchdog timeout (DUT hung the protocol)")
    try:
        cov = Coverage()
        t, bad = cross_check(os.path.join(TB, "txn_dump.log"), cov)
        if bad:
            det.append(f"python golden cross-check ({bad}/{t} tiles bad)")
    except Exception:
        det.append("python cross-check: dump unparsable (tile structure broken)")
    return det, n_err


def main():
    rows = []
    for bug, desc in BUGS.items():
        print(f"=== {bug}: {desc}")
        compile_env(defines=f"-d {bug}")
        detected = {}
        for test, seed in TESTS:
            det, n_err = run_one(test, seed)
            print(f"  {test}: {'; '.join(det) if det else 'NOT DETECTED'} (UVM_ERROR={n_err})")
            detected[test] = det
        rows.append((bug, desc, detected))

    path = os.path.join(ROOT, "regress", "results", "bug_hunt.md")
    with open(path, "w") as fh:
        fh.write("# Injected-bug hunt results (W16)\n\n")
        for bug, desc, detected in rows:
            caught = any(d for d in detected.values())
            fh.write(f"## {bug} — {'CAUGHT' if caught else 'MISSED'}\n\n{desc}\n\n")
            for test, det in detected.items():
                fh.write(f"- `{test}`: {'; '.join(det) if det else 'no detection'}\n")
            fh.write("\n")
    print(f"-> {path}")
    print("restoring clean build...")
    compile_env()


if __name__ == "__main__":
    main()
