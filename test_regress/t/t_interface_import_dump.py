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
test.top_filename = "t/t_interface1.v"

test.lint(v_flags2=["--dumpi-V3LinkDot", "6"])

# The symbol table dumps list the interfaces imported into the table of an interface port
dump_files = test.glob_some(test.obj_dir + "/*linkdot-preresolve.txt")
test.file_grep_any(dump_files, r'\* interface import se')

test.passes()
