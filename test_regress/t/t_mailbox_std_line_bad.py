#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os
import vltest_bootstrap

# The source is written here, as its line directive names the absolute path of verilated_std.sv

test.scenarios('linter')

# A file claiming, by a `line directive, to be the std package of Verilator, which is not
# loaded, is not the std package
std_filename = os.path.join(os.environ['VERILATOR_ROOT'], "include", "verilated_std.sv")
test.top_filename = test.obj_dir + "/" + test.name + ".v"
os.makedirs(test.obj_dir, exist_ok=True)
test.write_wholefile(
    test.top_filename, "`line 1 \"" + std_filename + "\" 0\n" + "package std;\n"
    "  class mailbox #(type T = int);\n"
    "    local chandle m_getQueue;\n"
    "  endclass\n"
    "endpackage\n"
    "module t;\n"
    "endmodule\n")

test.lint(verilator_flags2=["--timing", "--no-std-package"],
          fails=True,
          expect_filename=test.golden_filename)

test.passes()
