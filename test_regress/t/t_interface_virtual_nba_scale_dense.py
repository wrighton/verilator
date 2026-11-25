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

# Many clocked calls, each through a different method, into one chain of methods, each reading
# the same members
N = 64
test.top_filename = f"{test.obj_dir}/t_interface_virtual_nba_scale_dense.v"
with open(test.top_filename, "w", encoding="utf8") as f:
    members = " ^ ".join(f"q{j}" for j in range(N))
    f.write("interface ifc;\n")
    for j in range(N):
        f.write(f"  logic [14:0] q{j} = 0;\n")
    for k in range(N):
        rhs = f"{members} ^ f{k + 1}()" if k + 1 < N else members
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
    f.write(f"module t (input clk, input logic [14:0] d, output logic [14:0] o[{N}]);\n"
            "  ifc i ();\n"
            "  virtual ifc v = i;\n")
    for j in range(N):
        f.write(f"  always @(posedge clk) i.q{j} <= d ^ 15'({j});\n")
    for k in range(N):
        f.write(f"  always @(posedge clk) o[{k}] <= v.w{k}();\n")
    f.write("endmodule\n")

test.compile(verilator_flags2=['--stats', '-Wno-UNOPTTHREADS'], threads=4)

test.file_grep(test.stats, r'Scheduling, virtual interface read barriers\s+(\d+)', N)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier edges\s+(\d+)',
               N * N + 2 * N)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier move edges\s+(\d+)',
               N * N + 2 * N)

# Within the members of the functions times the members (50569 here); a search of the call graph
# for each call, revisiting the reads of each function, is cubic (over 275000 here)
steps = int(
    test.file_grep(test.stats, r'Scheduling, virtual interface read call graph steps\s+(\d+)')[0])
if steps > 120000:
    test.error("Finding virtual interface reads went cubic: {} steps".format(steps))

# Many calls, many reads of few members: the closures of the functions are memoized
test.file_grep(test.stats, r'Scheduling, virtual interface read closures memoized\s+(\d+)', 1)

test.passes()
