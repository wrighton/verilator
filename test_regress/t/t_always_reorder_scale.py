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

if test.have_dev_gcov:
    test.skip("Too slow with code coverage")

N_SMALL = 2500
N_LARGE = N_SMALL * 4
# Linear scaling gives 4x, quadratic gives 16x; allow for timer noise and machine load
MAX_RATIO = 10
# Ignore the ratio when reordering is fast enough that timer noise dominates
MIN_SECONDS = 2.0


def reorder_seconds(n):
    # Long blocks of statements writing a variable that later statements read, by blocking and by
    # nonblocking assignments
    test.top_filename = f"{test.obj_dir}/t_{n}.v"
    with open(test.top_filename, "w", encoding="utf8") as f:
        f.write("module t(input logic clk, input logic [62:0] in, output logic [62:0] out);\n")
        f.write("  logic [62:0] r;\n")
        f.write("  logic [62:0] q;\n")
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    logic [62:0] v;\n")
        f.write("    v = r ^ in;\n")
        for i in range(n):
            f.write(f"    v = (v << 1) ^ (v >> 3) ^ 63'(in[{i % 63}]);\n")
        f.write("    r <= v;\n")
        f.write("  end\n")
        f.write("  always_ff @(posedge clk) begin\n")
        f.write("    logic [62:0] a;\n")
        for i in range(n):
            f.write(f"    a = q ^ 63'(in[{i % 63}]);\n")
            f.write(f"    q <= a ^ 63'({i});\n")
        f.write("  end\n")
        f.write("  assign out = r ^ q;\n")
        f.write("endmodule\n")
    test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)
    # Read anew, as test.file_contents() keeps the contents of the first compile
    with open(test.stats, 'r', encoding="utf8") as fh:
        stats = fh.read()
    # Each blocking write of v, and each write of a or q but the last, comes ahead of a reader
    ignored = re.search(r'Optimizations, Reorder, edges into writers ahead of readers\s+(\d+)',
                        stats)
    if not ignored or int(ignored.group(1)) != 3 * n:
        test.error(f"Expected {3 * n} edges into writers ahead of readers in " + test.stats)
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_reorder\s+(\S+)', stats)
    if not times:
        test.error("Reorder time not found in " + test.stats)
    return sum(float(t) for t in times)


small = reorder_seconds(N_SMALL)
large = reorder_seconds(N_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Reordering time scaled superlinearly with block length: " +
               f"{N_SMALL} statements took {small:.3f}s, " +
               f"{N_LARGE} statements took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
