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

FUNCS = 2000

# A long chain of non-inlined functions, each calling the next, and a short recursive one
test.top_filename = f"{test.obj_dir}/t_func_noinline_purity_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write("module t (input clk, input [7:0] a, output logic [7:0] o, output int r);\n")
    for k in range(FUNCS):
        call = f" + g{k + 1}(x)" if k + 1 < FUNCS else ""
        fh.write(f"  function automatic logic [7:0] g{k}(logic [7:0] x);"
                 f" /*verilator no_inline_task*/ return x + 8'd{k % 256}{call}; endfunction\n")
    fh.write("  function automatic int fact(int n); /*verilator no_inline_task*/\n")
    fh.write("    return n <= 1 ? 1 : n * fact(n - 1);\n")
    fh.write("  endfunction\n")
    fh.write("  always_ff @(posedge clk) begin\n")
    fh.write("    o <= g0(a);\n")
    fh.write("    r <= fact(int'(a[2:0]));\n")
    fh.write("  end\n")
    fh.write("endmodule\n")

# A gcov -O0 build overflows the default stack recursing through the chain in V3Width
test.compile(verilator_flags2=["--stats", "--unlimited-stack"],
             make_main=False,
             verilator_make_gmake=False)

# Linear in the functions (a few per function here); finding the purity of each when freeing
# its body, which any edit clears, was quadratic (about FUNCS / 2 per function here)
purities = int(test.file_grep(test.stats, r'Optimizations, Function purities computed\s+(\d+)')[0])
if purities > 8 * FUNCS:
    test.error("Freeing function bodies went quadratic in call chain length: " +
               f"{purities} purities computed for {FUNCS} functions")

test.passes()
