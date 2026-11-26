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

REFS = 500

# An interface with many members, and many virtual interface references to it
test.top_filename = f"{test.obj_dir}/t_interface_ref_param_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write("interface ifc;\n")
    for k in range(REFS):
        fh.write(f"  logic [7:0] m{k};\n")
    fh.write("endinterface\n")
    fh.write("module t;\n")
    fh.write("  ifc i ();\n")
    for k in range(REFS):
        fh.write(f"  virtual ifc v{k} = i;\n")
    fh.write("endmodule\n")

test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)

# Linear in the references (a few statements each here); scanning the interface's statements
# for each reference was quadratic (about 2 * REFS each here)
scans = int(test.file_grep(test.stats, r'Param, Statements scanned for references\s+(\d+)')[0])
if scans > 8 * REFS:
    test.error("Parameterizing interface references went quadratic in interface size: " +
               f"{scans} statements scanned for {REFS} references")

test.passes()
