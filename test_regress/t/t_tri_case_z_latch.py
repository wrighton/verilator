#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import glob

import vltest_bootstrap

test.scenarios('vlt')

test.lint(
    verilator_flags2=["--dump-tree", "--dump-tree-json", "-Wno-CASEINCOMPLETE", "-Wno-CASEWITHX"],
    fails=True,
    expect_filename=test.golden_filename)

# The case statements missing values are known to be incomplete once rewritten
test.file_grep(glob.glob(test.obj_dir + "/*_tristate.tree")[0], r'CASE .*\[INCOMPLETE\]')
test.file_grep(glob.glob(test.obj_dir + "/*_tristate.tree.json")[0], r'"incomplete":true')

test.passes()
