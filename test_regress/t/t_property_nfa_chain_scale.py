#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')

STEPS = 1024

# Assertions with a rejecting step, and a throughout guard, per cycle, written out
test.top_filename = f"{test.obj_dir}/t_property_nfa_chain_scale.v"
seq = " ##1 ".join("a" if i % 2 == 0 else "!a" for i in range(STEPS))
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("module t (input clk, input a, input b, input c);\n")
    f.write(f"  assert property (@(posedge clk) {seq} ##1 b);\n")
    f.write(f"  assert property (@(posedge clk) c throughout ({seq}));\n")
    f.write("endmodule\n")

test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)

# Linear in the steps (300 per step here); ORing the reject conditions in one chain made
# constant folding revisit it, quadratic (over 2000 per step here)
visits = int(test.file_grep(test.stats, r'Optimizations, Const and/or visits\s+(\d+)')[0])
if visits > 600 * STEPS:
    test.error("Constant folding went quadratic in assertion length: " +
               f"{visits} and/or visits for {STEPS} steps")

test.passes()
