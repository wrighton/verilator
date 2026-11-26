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

TERMS = 4000

# Long chains of 1-bit '||' and '&&', one term per line
test.top_filename = f"{test.obj_dir}/t_const_logic_chain_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write(f"module t (input [{TERMS - 1}:0] a, output o_or, output o_and);\n")
    for out, op in (("o_or", "||"), ("o_and", "&&")):
        fh.write(f"  assign {out} = " + f"\n    {op} ".join(f"a[{i}]"
                                                            for i in range(TERMS)) + ";\n")
    fh.write("endmodule\n")

test.compile(verilator_flags2=["--stats", "--no-debug-check", "--unlimited-stack"],
             make_main=False,
             verilator_make_gmake=False)

# Linear in the terms (about 12 per term here); revisiting the operands below each operator
# converted from logical to bitwise was quadratic (about 4000 per term here)
visits = int(test.file_grep(test.stats, r'Optimizations, Const and/or visits\s+(\d+)')[0])
if visits > 25 * TERMS:
    test.error("Constant folding went quadratic in logical operator chain length: " +
               f"{visits} and/or visits for {TERMS} terms")

test.passes()
