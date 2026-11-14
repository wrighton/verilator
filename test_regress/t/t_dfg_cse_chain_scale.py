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

STAGES_SMALL = 1000
STAGES_LARGE = STAGES_SMALL * 8
# Linear scaling gives 8x, quadratic gives 64x
MAX_RATIO = 16
# Ignore the ratio when CSE is fast enough that timer noise dominates
MIN_SECONDS = 0.1


def cse_seconds(stages):
    # A long chain of identically shaped stages, each reading the previous one twice
    test.top_filename = f"{test.obj_dir}/t_{stages}.v"
    with open(test.top_filename, "w", encoding="utf8") as fh:
        fh.write("module t (input [7:0] a, output [7:0] y);\n")
        for i in range(stages + 1):
            fh.write(f"  wire [7:0] w{i};\n")
        fh.write("  assign w0 = a;\n")
        for i in range(stages):
            fh.write(f"  assign w{i + 1} = w{i} ^ {{w{i}[6:0], w{i}[7]}};\n")
        fh.write(f"  assign y = w{stages};\n")
        fh.write("endmodule\n")
    test.compile(verilator_flags2=["--stats", "--no-debug-check"],
                 make_main=False,
                 verilator_make_gmake=False)
    with open(test.stats, "r", encoding="utf8") as fh:
        stats = fh.read()
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_dfg-cse\S*\s+(\S+)', stats)
    if not times:
        test.error("Dfg CSE time not found in " + test.stats)
    return sum(float(t) for t in times)


small = cse_seconds(STAGES_SMALL)
large = cse_seconds(STAGES_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Dfg CSE time scaled superlinearly with chain length: " +
               f"{STAGES_SMALL} stages took {small:.3f}s, " +
               f"{STAGES_LARGE} stages took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
