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
test.top_filename = 't/t_assert_ctl_mixed_table.v'
test.compile(verilator_flags2=[
    '--binary', '--assert', '--stats', '+define+VIA_PORT+VIA_FORWARD+VIA_COHORTS+VIA_COMMON+VIA_TOP',
    '+define+N=2', '+define+COMMON_N=5', '--dumpi-tree 3', '--debug-emitv'
], threads=1)
test.execute()
# Keep the top list shared and the two bank selections in caller overlays.
test.file_grep(test.stats, r'Assertions, Shared absolute target lists\s+(\d+)', 2)
test.file_grep(test.glob_one(test.obj_dir + '/*_scope.tree'), r'\bASSERTCTLTARGETSET\b')
test.file_grep_not(test.glob_one(test.obj_dir + '/*_scope.tree.v'), r'ASSERTCTLTARGETSET|ASSERTCTLTARGET')
test.passes()
