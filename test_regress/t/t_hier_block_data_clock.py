#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(
    verilator_flags2=['--binary', '--hierarchical', '--stats', '--dump-tree', '--dump-tree-json'])

# en and ft
test.file_grep(test.obj_dir + '/Vsrc_h/Vsrc_h__stats.txt',
               r'Scheduling, library outputs of the data inputs alone\s+(\d+)', 2)
test.file_grep(test.glob_one(test.obj_dir + '/Vsrc_h/Vsrc_h_*_sched.tree'),
               r'ft OUTPUT .*\[PDATA\]')
# The clock update of src_h is not in the active region of the model using it (91 before)
test.file_grep(test.obj_dir + '/V' + test.name + '__hier.dir/V' + test.name + '__stats.txt',
               r'Scheduling, size of region: Active\s+(\d+)', 36)

test.execute()

test.passes()
