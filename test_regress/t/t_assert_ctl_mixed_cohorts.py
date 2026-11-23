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
test.top_filename = 't/t_assert_ctl_mixed_table.v'
n = 8 if test.vltmt else 4
test.compile(verilator_flags2=[
    '--binary', '--assert', '--stats', '+define+VIA_PORT+VIA_FORWARD+VIA_COHORTS', f'+define+N={n}'
], threads=2 if test.vltmt else 1)
test.execute()
# Two banks with N sites and N two-row overlays each, plus two hierarchical callers.
test.file_grep(test.stats, r'Assertions, Scoped table entries\s+(\d+)', 6 * n + 2 * (n + 1))
test.file_grep(test.stats, r'Assertions, Shared absolute target lists\s+(\d+)', 2)

test.passes()
