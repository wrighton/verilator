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

# Keep selects of wide values for the runtime library, and take X as one, so the bits of a
# 4-state selection out of range are distinct
# Without Dfg and Expand, which can fold selects first, and with X read as ones
test.compile(verilator_flags2=[
    "--binary", "-fno-dfg", "-fno-expand", "--x-assign 1", "+define+X_ONE", "--stats"
])

test.execute(all_run_flags=["+pos2=17", "+pos4=4294967"])

test.file_grep(test.stats, r'Unknowns, partial range reads\s+(\d+)', 141)

test.passes()
