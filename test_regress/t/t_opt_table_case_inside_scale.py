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

SEL_BITS = 10
ITEMS_SMALL = 128
ITEMS_LARGE = ITEMS_SMALL * 8
# Linear scaling gives 8x, quadratic gives 64x
MAX_RATIO = 16
# Ignore the ratio when table creation is fast enough that timer noise dominates
MIN_SECONDS = 0.2


def table_seconds(items):
    # A 'case inside' of single-value ranges becomes a long conditional chain, which V3Table
    # simulates once per selector value; most values fall through the whole chain
    test.top_filename = f"{test.obj_dir}/t_{items}.v"
    step = (1 << SEL_BITS) // items
    with open(test.top_filename, "w", encoding="utf8") as fh:
        fh.write(f"module t (input [{SEL_BITS - 1}:0] a, output logic [15:0] y);\n")
        fh.write("  always_comb begin\n")
        fh.write("    case (a) inside\n")
        for i in range(items):
            fh.write(f"      [{i * step}:{i * step}]: y = 16'd{i + 1};\n")
        fh.write("      default: y = '0;\n")
        fh.write("    endcase\n")
        fh.write("  end\n")
        fh.write("endmodule\n")
    test.compile(verilator_flags2=["--stats", "--no-debug-check"],
                 make_main=False,
                 verilator_make_gmake=False)
    test.file_grep(test.stats, r'Optimizations, Tables created\s+(\d+)', 1)
    with open(test.stats, "r", encoding="utf8") as fh:
        stats = fh.read()
    times = re.findall(r'Stage, Elapsed time \(sec\), \d+_table\s+(\S+)', stats)
    if not times:
        test.error("Table time not found in " + test.stats)
    return sum(float(t) for t in times)


small = table_seconds(ITEMS_SMALL)
large = table_seconds(ITEMS_LARGE)
if large > MIN_SECONDS and large > small * MAX_RATIO:
    test.error("Table creation time scaled superlinearly with conditional chain length: " +
               f"{ITEMS_SMALL} items took {small:.3f}s, " +
               f"{ITEMS_LARGE} items took {large:.3f}s (over {MAX_RATIO}x)")

test.passes()
