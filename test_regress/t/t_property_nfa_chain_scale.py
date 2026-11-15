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

STEPS_SMALL = 64
STEPS_LARGE = STEPS_SMALL * 4
# Linear scaling gives 4x, quadratic gives 16x
MAX_RATIO = 8
# Ignore the ratio when constant folding is fast enough that timer noise dominates
MIN_SECONDS = 0.1


def const_seconds(steps):
    # Assertions with a rejecting step, and a throughout guard, per cycle, written out
    test.top_filename = f"{test.obj_dir}/t_{steps}.v"
    seq = " ##1 ".join("a" if i % 2 == 0 else "!a" for i in range(steps))
    with open(test.top_filename, "w", encoding="utf8") as f:
        f.write("module t (input clk, input a, input b, input c);\n")
        f.write(f"  assert property (@(posedge clk) {seq} ##1 b);\n")
        f.write(f"  assert property (@(posedge clk) c throughout ({seq}));\n")
        f.write("endmodule\n")
    test.compile(verilator_flags2=["--stats"],
                 make_main=False,
                 verilator_make_gmake=False)
    stats = test.file_contents(test.stats)
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_const\S*\s+(\S+)', stats)
    if not times:
        test.error("Const time not found in " + test.stats)
    return sum(float(t) for t in times)


small = const_seconds(STEPS_SMALL)
large = const_seconds(STEPS_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Constant folding time scaled superlinearly with assertion length: " +
               f"{STEPS_SMALL} steps took {small:.3f}s, " +
               f"{STEPS_LARGE} steps took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
