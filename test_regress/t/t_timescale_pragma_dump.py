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

test.lint(v_flags=["--dump-tree", "--dump-tree-json"])

tree = test.glob_some(test.obj_dir + "/*_002_cellsort.tree")[0]
test.file_grep(tree, r'PRAGMA .* INLINE_MODULE\n')
test.file_grep(tree, r'TIMEUNIT_SET timescale=1ns')
test.file_grep(tree, r'TIMEPRECISION_SET timescale=1ps')
tree_json = test.glob_some(test.obj_dir + "/*_002_cellsort.tree.json")[0]
test.file_grep(tree_json, r'"pragType":"TIMEPRECISION_SET","timescale":"1ps"')

test.passes()
