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

MEMBERS = 4000

# An interface with many members, each read through a virtual interface
test.top_filename = f"{test.obj_dir}/t_interface_member_ref_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write("interface ifc;\n")
    for k in range(MEMBERS):
        fh.write(f"  logic [7:0] m{k};\n")
    fh.write("endinterface\n")
    fh.write("module t (output logic [7:0] o);\n")
    fh.write("  ifc i ();\n")
    fh.write("  virtual ifc h = i;\n")
    fh.write("  always_comb begin\n")
    fh.write("    o = 0;\n")
    for k in range(MEMBERS):
        fh.write(f"    o = o ^ h.m{k};\n")
    fh.write("  end\n")
    fh.write("endmodule\n")

test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)

# Linear in the references (one lookup each here); scanning the interface's items for each
# reference was quadratic (about MEMBERS / 2 each here)
steps = int(test.file_grep(test.stats, r'Width, Interface member lookup steps\s+(\d+)')[0])
if steps > 4 * MEMBERS:
    test.error("Interface member references went quadratic in interface size: " +
               f"{steps} lookup steps for {MEMBERS} members")

test.passes()
