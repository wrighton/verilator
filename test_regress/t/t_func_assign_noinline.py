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

test.compile(verilator_flags2=["--binary", "--stats"])

test.execute(all_run_flags=["+names=n1,n3"])

# Not inlined: the 6 in_names calls, and the get5, pop_first, plus_c, forced_lhs, 2 top_tw, 4 calls
# of set_wf1, wf1, wf2 and set_wf2, fact_sq_f, early_w, ret_rw and mark calls
test.file_grep(test.stats,
               r'Optimizations, Function calls in initial assignments not inlined\s+(\d+)', 20)

test.passes()
