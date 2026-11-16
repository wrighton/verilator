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
if test.have_dev_asan or test.tsan:
    test.skip("Too slow with sanitizers")

INSTS_SMALL = 250
INSTS_LARGE = INSTS_SMALL * 8
# Linear scaling gives 8x, quadratic gives 64x
MAX_RATIO = 32
# Ignore the ratio when widthing is fast enough that timer noise dominates
MIN_SECONDS = 0.1


def width_seconds(insts):
    # Arrays of interfaces, connected to module instances by constant element selects of a one
    # and of a two dimensional array, and by constant slices
    test.top_filename = f"{test.obj_dir}/t_{insts}.v"
    with open(test.top_filename, "w", encoding="utf8") as fh:
        fh.write("interface bus_if;\n")
        fh.write("  logic [7:0] d;\n")
        fh.write("endinterface\n")
        fh.write("module drv (bus_if b, input [7:0] x);\n")
        fh.write("  assign b.d = x;\n")
        fh.write("endmodule\n")
        fh.write("module drv2 (bus_if p[2], input [7:0] x);\n")
        fh.write("  assign p[0].d = x;\n")
        fh.write("  assign p[1].d = ~x;\n")
        fh.write("endmodule\n")
        fh.write(f"module t (input [7:0] x[{insts}], output [7:0] y[{insts}]);\n")
        fh.write(f"  bus_if b[{insts}:1] ();\n")
        fh.write(f"  bus_if c[0:0][{insts}:1] ();\n")
        fh.write(f"  bus_if s[{2 * insts}:1] ();\n")
        fh.write(f"  for (genvar i = 1; i <= {insts}; ++i) begin : g\n")
        fh.write("    drv ub (.b(b[i]), .x(x[i - 1]));\n")
        fh.write("    drv uc (.b(c[0][i]), .x(x[i - 1]));\n")
        fh.write("    drv2 us (.p(s[2 * i:2 * i - 1]), .x(x[i - 1]));\n")
        fh.write("    assign y[i - 1] = b[i].d ^ c[0][i].d ^ s[2 * i].d;\n")
        fh.write("  end\n")
        fh.write("endmodule\n")
    test.compile(verilator_flags2=["--stats", "--no-debug-check"],
                 make_main=False,
                 verilator_make_gmake=False)
    with open(test.stats, "r", encoding="utf8") as fh:
        stats = fh.read()
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_width\s+(\S+)', stats)
    if not times:
        test.error("Width time not found in " + test.stats)
    return sum(float(t) for t in times)


small = width_seconds(INSTS_SMALL)
large = width_seconds(INSTS_LARGE)
print(f"{INSTS_SMALL} instances took {small:.3f}s, {INSTS_LARGE} took {large:.3f}s")
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Width time scaled superlinearly with interface array selects: " +
               f"{INSTS_SMALL} instances took {small:.3f}s, " +
               f"{INSTS_LARGE} instances took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
