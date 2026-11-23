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
test.top_filename = "t/t_select_bit_narrow.v"

test.compile(verilator_flags2=["--binary", "--dump-tree", "--dump-tree-json"])

# Part-selects marked as written partly out of range are dumped as such
test.file_grep(test.glob_one(test.obj_dir + "/*_unknown.tree"), r'\[PARTIALW\]')
test.file_grep(test.glob_one(test.obj_dir + "/*_unknown.tree.json"), r'"partialWrite":true')

test.execute(all_run_flags=["+pos2=17", "+pos4=4294967"])

test.passes()
