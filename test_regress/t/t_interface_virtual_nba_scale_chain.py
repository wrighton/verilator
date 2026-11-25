#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vltmt')

# One clocked read through a virtual interface into a long chain of methods, each reading a member
# of its own and calling the next
N = 128
test.top_filename = f"{test.obj_dir}/t_interface_virtual_nba_scale_chain.v"
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("interface ifc;\n")
    for k in range(N):
        f.write(f"  logic [14:0] q{k} = 0;\n")
    for k in range(N):
        rhs = f"q{k} ^ f{k + 1}()" if k + 1 < N else f"q{k}"
        f.write(f"  function automatic logic [14:0] f{k}();\n"
                "    // verilator no_inline_task\n"
                f"    return {rhs};\n"
                "  endfunction\n")
    f.write("endinterface\n")
    f.write("module t (input clk, input logic [14:0] d, output logic [14:0] o);\n"
            "  ifc i ();\n"
            "  virtual ifc v = i;\n")
    for k in range(N):
        f.write(f"  always @(posedge clk) i.q{k} <= d ^ 15'({k});\n")
    f.write("  always @(posedge clk) o <= v.f0() + o;\n"
            "endmodule\n")

test.compile(verilator_flags2=['--stats', '-Wno-UNOPTTHREADS'], threads=4)

test.file_grep(test.stats, r'Scheduling, virtual interface read barriers\s+(\d+)', N)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier edges\s+(\d+)', 3 * N)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier move edges\s+(\d+)', 3 * N)

# Linear in the functions and members (772 here); keeping the members of each function along
# the chain is quadratic (over 9000 here)
steps = int(
    test.file_grep(test.stats, r'Scheduling, virtual interface read call graph steps\s+(\d+)')[0])
if steps > 2000:
    test.error("Finding virtual interface reads went quadratic: {} steps".format(steps))

# One call, many members: the call searches the call graph
test.file_grep(test.stats, r'Scheduling, virtual interface read closures memoized\s+(\d+)', 0)

test.passes()
