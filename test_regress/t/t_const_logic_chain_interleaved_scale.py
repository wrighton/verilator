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

TERMS = 2000
WITHIN = 200

# A long chain of 1-bit '||' of '&&', one term per line, and the chain of '||' of '&&' that
# a long 'within' lowers to
test.top_filename = f"{test.obj_dir}/t_const_logic_chain_interleaved_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write(
        f"module t (input clk, input [{TERMS - 1}:0] a, input [{TERMS - 1}:0] b, output o);\n")
    fh.write("  assign o = " + "\n    || ".join(f"(a[{i}] && b[{i}])"
                                                for i in range(TERMS)) + ";\n")
    fh.write(f"  cover property (@(posedge clk) (a[0] ##1 a[1]) within (a[2] ##{WITHIN} a[3]));\n")
    fh.write("endmodule\n")

test.compile(verilator_flags2=["--assert", "--stats", "--no-debug-check", "--unlimited-stack"],
             make_main=False,
             verilator_make_gmake=False)

# Linear in the terms (about 7 per term here); checking the purity of the whole chain below each
# '||' converted from logical to bitwise after its '&&' operand was quadratic (about 2 per term
# per term here)
purities = int(
    test.file_grep(test.stats, r'Optimizations, Const logic purities computed\s+(\d+)')[0])
if purities > 10 * (TERMS + 4 * WITHIN):
    test.error("Constant folding went quadratic in logical operator chain length: " +
               f"{purities} purities computed for {TERMS} terms and a {WITHIN} cycle within")

test.passes()
