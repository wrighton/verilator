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

# Many clocked calls, each through a different method, into a dense call graph: one function calls
# N functions, each of which calls the same N functions reading one member
N = 192
test.top_filename = f"{test.obj_dir}/t_interface_virtual_nba_scale_calls.v"
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("interface ifc;\n"
            "  logic [14:0] q = 0;\n")
    for k in range(N):
        f.write(f"  function automatic logic [14:0] f{k}();\n"
                "    // verilator no_inline_task\n"
                f"    return q + 15'({k});\n"
                "  endfunction\n")
    leaves = " + ".join(f"f{k}()" for k in range(N))
    for k in range(N):
        f.write(f"  function automatic logic [14:0] m{k}();\n"
                "    // verilator no_inline_task\n"
                f"    return {leaves};\n"
                "  endfunction\n")
    middles = " + ".join(f"m{k}()" for k in range(N))
    f.write("  function automatic logic [14:0] common();\n"
            "    // verilator no_inline_task\n"
            f"    return {middles};\n"
            "  endfunction\n")
    for k in range(N // 8):
        f.write(f"  function automatic logic [14:0] w{k}();\n"
                "    // verilator no_inline_task\n"
                "    return common();\n"
                "  endfunction\n")
    f.write("endinterface\n")
    f.write(f"module t (input clk, input logic [14:0] d, output logic [14:0] o[{N // 8}]);\n"
            "  ifc i ();\n"
            "  virtual ifc v = i;\n"
            "  always @(posedge clk) i.q <= d;\n")
    for k in range(N // 8):
        f.write(f"  always @(posedge clk) o[{k}] <= v.w{k}();\n")
    f.write("endmodule\n")

test.compile(verilator_flags2=['--stats', '-Wno-UNOPTTHREADS'], threads=4)

test.file_grep(test.stats, r'Scheduling, virtual interface read barriers\s+(\d+)', 1)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier edges\s+(\d+)', N // 8 + 2)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier move edges\s+(\d+)',
               N // 8 + 2)

# Within the calls between the functions times the members (224820 here); a search of the call
# graph for each call, following every call between the functions, is cubic (over 940000 here)
steps = int(
    test.file_grep(test.stats, r'Scheduling, virtual interface read call graph steps\s+(\d+)')[0])
if steps > 400000:
    test.error("Finding virtual interface reads went cubic: {} steps".format(steps))

# Many calls through a dense call graph to one member: the closures of the functions are memoized
test.file_grep(test.stats, r'Scheduling, virtual interface read closures memoized\s+(\d+)', 1)

test.passes()
