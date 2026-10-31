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

test.compile(verilator_flags2=["--comp-limit-members", "3", "--vpi", "--trace-vcd"])

test.execute()

prefix = test.obj_dir + "/" + test.vm_prefix
# More than 3*3 members: named structs (retained clk/cyc ports add two members)
test.file_grep(prefix + "___024root.h", r'\} __Vg\d+;')
test.file_grep(prefix + "_sub__N28.h", r'\} __Vg\d+;')
test.file_grep(prefix + "_sub__Na.h", r'\} __Vg\d+;')
test.file_grep(prefix + "_sub__N9.h", r'\} __Vg\d+;')
# Just above the boundary: 8 registers + retained clk/cyc ports = 10 members.
test.file_grep(prefix + "_sub__N8.h", r'\} __Vg\d+;')
test.file_grep(prefix + "___024root__0.cpp",
               r'vlSelfRef\.__Vg\d+\.__Vg\d+\.__Vg\d+\.t__DOT__gen__BRA__')
# Public members are in anonymous structs and accessed directly
test.file_grep(prefix + "___024root.h", r'__DOT__pubr;\n\s*\};')
test.file_grep(prefix + "___024root__0.cpp", r'vlSelfRef\.t__DOT__gen__BRA__\d+__KET____DOT__pubr')
test.file_grep(prefix + "__Syms__Slow.cpp",
               r'offsetof\(Vt_emit_memb_limit_triv___024root, t__DOT__pub\)')
# At most 3*3 members (sub__N7 has 7 registers + clk/cyc), and class members: anonymous structs
for name in ["_sub__N7", "___024unit__03A__03ABase__Vclpkg"]:
    test.file_grep_not(prefix + name + ".h", r'\} __Vg')
    test.file_grep(prefix + name + ".h", r'struct \{')

test.passes()
