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

# Many clocked calls into shared chains of functions, each reading one member at its end: readers
# each through a different method calling the head of one chain of methods, and readers each
# calling a different function along one chain of functions taking a virtual interface argument
N = 128
test.top_filename = f"{test.obj_dir}/t_interface_virtual_nba_scale_roots.v"
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("interface ifc;\n"
            "  logic [14:0] q = 0;\n"
            "  logic [14:0] p = 0;\n")
    for k in range(N):
        rhs = f"f{k + 1}()" if k + 1 < N else "q"
        f.write(f"  function automatic logic [14:0] f{k}();\n"
                "    // verilator no_inline_task\n"
                f"    return {rhs};\n"
                "  endfunction\n")
    for k in range(N):
        f.write(f"  function automatic logic [14:0] w{k}();\n"
                "    // verilator no_inline_task\n"
                f"    return f0() ^ 15'({k});\n"
                "  endfunction\n")
    f.write("endinterface\n")
    f.write(f"module t (input clk, input logic [14:0] d, output logic [14:0] o[{N}],\n"
            f"          output logic [14:0] r[{N}]);\n"
            "  ifc i ();\n"
            "  virtual ifc v = i;\n"
            "  always @(posedge clk) begin\n"
            "    i.q <= d;\n"
            "    i.p <= d ^ 15'h1234;\n"
            "  end\n")
    for k in range(N):
        f.write(f"  always @(posedge clk) o[{k}] <= v.w{k}();\n")
    for k in range(N):
        rhs = f"h{k + 1}(b) + 15'd1" if k + 1 < N else "b.p"
        f.write(f"  function automatic logic [14:0] h{k}(virtual ifc b);\n"
                "    // verilator no_inline_task\n"
                f"    return {rhs};\n"
                "  endfunction\n")
    for k in range(N):
        f.write(f"  always @(posedge clk) r[{k}] <= h{k}(v);\n")
    f.write("endmodule\n")

test.compile(verilator_flags2=['--stats', '-Wno-UNOPTTHREADS'], threads=4)

test.file_grep(test.stats, r'Scheduling, virtual interface read barriers\s+(\d+)', 2)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier edges\s+(\d+)', 2 * N + 4)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier move edges\s+(\d+)',
               2 * N + 4)

# Linear in the functions and members (6521 here); a search of the call graph for each call is
# quadratic (over 50000 here)
steps = int(
    test.file_grep(test.stats, r'Scheduling, virtual interface read call graph steps\s+(\d+)')[0])
if steps > 8000:
    test.error("Finding virtual interface reads went quadratic: {} steps".format(steps))

# Many calls, few members: the closures of the functions are memoized
test.file_grep(test.stats, r'Scheduling, virtual interface read closures memoized\s+(\d+)', 1)

test.passes()
