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

CLOCKS_SMALL = 200
CLOCKS_LARGE = CLOCKS_SMALL * 8
# Linear scaling gives 8x, quadratic gives 64x
MAX_RATIO = 16
# Ignore the ratio when V3Delayed is fast enough that timer noise dominates
MIN_SECONDS = 0.1


def delayed_seconds(clocks):
    # Elements of one array updated by non-blocking assignments, each under its own clock
    test.top_filename = f"{test.obj_dir}/t_{clocks}.v"
    with open(test.top_filename, "w", encoding="utf8") as fh:
        fh.write(f"module t (input [{clocks - 1}:0] clk, input [7:0] d,\n")
        fh.write(f"          output logic [7:0] q[{clocks}]);\n")
        fh.write(f"  for (genvar i = 0; i < {clocks}; ++i) begin : g\n")
        fh.write("    always_ff @(posedge clk[i]) q[i] <= d + 8'(i);\n")
        fh.write("  end\n")
        fh.write("endmodule\n")
    test.compile(verilator_flags2=["--stats", "--no-debug-check"],
                 make_main=False,
                 verilator_make_gmake=False)
    with open(test.stats, "r", encoding="utf8") as fh:
        stats = fh.read()
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_delayed\s+(\S+)', stats)
    if not times:
        test.error("Delayed time not found in " + test.stats)
    return sum(float(t) for t in times)


small = delayed_seconds(CLOCKS_SMALL)
large = delayed_seconds(CLOCKS_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("V3Delayed time scaled superlinearly with clocks updating one variable: " +
               f"{CLOCKS_SMALL} clocks took {small:.3f}s, " +
               f"{CLOCKS_LARGE} clocks took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
