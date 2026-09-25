"""Generic Yosys synthesis of the MAC array and its parts -> cell-count table.

Usage:  python synth/run_synth.py            (needs `yosys` or `pip install yowasp-yosys`)

Every target goes through `synth -top <T> -flatten -noabc` and `stat -tech cmos`.
-noabc: the YoWASP (WebAssembly) Yosys build used here exits silently inside the ABC pass on
Windows, so the netlist is Yosys's own techmapped gate netlist ($_AND_/$_OR_/$_XOR_/$_MUX_/
$_NOT_ + flops), NOT an ABC-optimised or liberty-mapped one. Counts are therefore an upper-
bound-style structural measure, good for relative comparisons (multiplier vs adder), not area.
Logs land in synth/out/<target>.log; the markdown table is printed and written to
synth/out/summary.md.
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
RTL = "../rtl/mac_pe.sv ../rtl/ctrl.sv ../rtl/mac_array_4x4.sv"

TARGETS = [                                   # (top, sources, note)
    ("pe_mul", "pe_parts.sv", "8x8 signed multiplier (a*b)"),
    ("pe_add", "pe_parts.sv", "32b + sign-extended 16b adder"),
    ("pe_reg", "pe_parts.sv", "32b accumulator register w/ rst/clr/en"),
    ("mac_pe", RTL, "one PE (all of the above)"),
    ("ctrl", RTL, "tile FSM"),
    ("mac_array_4x4", RTL, "full 4x4 array (16 PE + ctrl + c_row mux)"),
]


def yosys_cmd():
    for exe in ("yosys", "yowasp-yosys"):
        if shutil.which(exe):
            return exe
    sys.exit("no yosys found: pip install yowasp-yosys")


def run(top, srcs):
    # YoWASP runs in a WASI sandbox that only sees the working directory tree, so paths
    # are relative to the repo root (cwd = repo root).
    srcs = " ".join(os.path.relpath(os.path.join(HERE, s), os.path.dirname(HERE)).replace("\\", "/")
                    for s in srcs.split())
    script = f"read_verilog -sv {srcs}; synth -top {top} -flatten -noabc; stat -tech cmos"
    p = subprocess.run([yosys_cmd(), "-p", script], cwd=os.path.dirname(HERE),
                       capture_output=True, encoding="utf-8", errors="replace")
    log = p.stdout + p.stderr
    with open(os.path.join(OUT, f"{top}.log"), "w", encoding="utf-8") as fh:
        fh.write(log)
    if p.returncode != 0:
        sys.exit(f"yosys failed on {top}; see synth/out/{top}.log")
    stat = log[log.rindex("Printing statistics"):]
    cells = {m.group(2): int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+(\$_\w+)", stat, re.M)}
    total = int(re.search(r"^\s+(\d+) cells", stat, re.M).group(1)) - cells.get("$scopeinfo", 0)
    tr = re.search(r"Estimated number of transistors:\s+(\d+\+?)", stat)
    return cells, total, tr.group(1) if tr else "n/a"


def main():
    os.makedirs(OUT, exist_ok=True)
    kinds = ["$_AND_", "$_OR_", "$_XOR_", "$_MUX_", "$_NOT_"]
    lines = ["| target | what | logic cells | AND | OR | XOR | MUX | NOT | flops | est. transistors (logic only) |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for top, srcs, note in TARGETS:
        cells, total, tr = run(top, srcs)
        flops = sum(v for k, v in cells.items() if "DFF" in k)
        logic = total - flops
        lines.append(f"| `{top}` | {note} | {logic} | " +
                     " | ".join(str(cells.get(k, 0)) for k in kinds) + f" | {flops} | {tr} |")
        print(f"{top:14s} logic={logic:6d} flops={flops:4d} transistors={tr}")
    table = "\n".join(lines) + "\n"
    with open(os.path.join(OUT, "summary.md"), "w", encoding="utf-8") as fh:
        fh.write(table)
    print(table)


if __name__ == "__main__":
    main()
