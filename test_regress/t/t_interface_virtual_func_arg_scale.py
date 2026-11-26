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

# An interface with many members, read by many functions, each through a virtual interface
# argument of its own
N = 256
test.top_filename = f"{test.obj_dir}/t_interface_virtual_func_arg_scale.v"
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("interface ifc;\n")
    for k in range(N):
        f.write(f"  logic [7:0] m{k} = 0;\n")
    f.write("endinterface\n")
    f.write("module t (input clk, output logic [7:0] o);\n"
            "  ifc i ();\n"
            "  virtual ifc v = i;\n"
            "  always_ff @(posedge clk) begin\n")
    for k in range(N):
        f.write(f"    i.m{k} <= i.m{k} + 8'd1;\n")
    f.write("  end\n")
    for k in range(N):
        rhs = f"h.m{k} + g{k + 1}(h)" if k + 1 < N else f"h.m{k}"
        f.write(f"  function automatic logic [7:0] g{k}(virtual ifc h);\n"
                "    // verilator no_inline_task\n"
                f"    return {rhs};\n"
                "  endfunction\n")
    f.write("  always_ff @(posedge clk) o <= g0(v);\n"
            "endmodule\n")

test.compile(verilator_flags2=['--stats'])

# Interface symbols are imported through each argument on lookup; importing every member for
# each argument was quadratic (over 65000 in each pass here)
for step in ('primary', 'paramed'):
    imported = int(
        test.file_grep(test.stats,
                       r'LinkDot, Interface symbols imported, ' + step + r'\s+(\d+)')[0])
    if imported > 2 * N:
        test.error("Importing interface symbols went quadratic: {} in {}".format(imported, step))

test.passes()
