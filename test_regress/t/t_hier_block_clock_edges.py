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

test.compile(verilator_flags2=[
    '--binary', '--hierarchical', '--vpi', '--stats', '--dump-tree', '--dump-tree-json'
])

# The two clocks of rising edges alone update at falling edges without copying any port
test.file_grep(test.obj_dir + '/Vblk_h/Vblk_h__stats.txt',
               r'Scheduling, library clocks of rising edges alone\s+(\d+)', 2)

test.file_grep(test.glob_one(test.obj_dir + '/Vblk_h/Vblk_h_*_sched.tree'),
               r'clk_a INPUT .*\[PPOS\]')

test.execute()

test.passes()
