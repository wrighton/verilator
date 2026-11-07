#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.scenarios('vlt')

TERMS_SMALL = 1000
TERMS_LARGE = TERMS_SMALL * 4
# Linear scaling gives 4x, quadratic gives 16x
MAX_RATIO = 8
# Ignore the ratio when constant folding is fast enough that timer noise dominates
MIN_SECONDS = 0.1


def const_seconds(terms):
    # Long chains of 1-bit '||' and '&&', one term per line
    test.top_filename = f"{test.obj_dir}/t_{terms}.v"
    with open(test.top_filename, "w", encoding="utf8") as fh:
        fh.write(f"module t (input [{terms - 1}:0] a, output o_or, output o_and);\n")
        for out, op in (("o_or", "||"), ("o_and", "&&")):
            fh.write(f"  assign {out} = " + f"\n    {op} ".join(f"a[{i}]" for i in range(terms)) +
                     ";\n")
        fh.write("endmodule\n")
    test.compile(verilator_flags2=["--stats", "--no-debug-check"],
                 make_main=False,
                 verilator_make_gmake=False)
    with open(test.stats, "r", encoding="utf8") as fh:
        stats = fh.read()
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_const\S*\s+(\S+)', stats)
    if not times:
        test.error("Const time not found in " + test.stats)
    return sum(float(t) for t in times)


small = const_seconds(TERMS_SMALL)
large = const_seconds(TERMS_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Constant folding time scaled superlinearly with logical operator chain length: " +
               f"{TERMS_SMALL} terms took {small:.3f}s, " +
               f"{TERMS_LARGE} terms took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
