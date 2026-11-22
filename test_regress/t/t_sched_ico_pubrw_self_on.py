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
test.top_filename = "t/t_sched_ico_pubrw_self.v"
test.pli_filename = "t/t_sched_ico_pubrw_self.cpp"

# The readers calling C++ code that is not pure do not have the variables they read change
# detected, so the evaluation converges as without the option
test.compile(make_top_shell=False,
             make_main=False,
             verilator_flags2=[
                 "--exe", "--stats", "--converge-limit 5", "-fico-public-change-detect",
                 test.pli_filename
             ])

test.execute()
test.execute(all_run_flags=["+cross"])

test.file_grep(test.stats, r"Scheduling, 'ico' public variable change detects\s+(\d+)", 1)
test.file_grep(test.stats,
               r"Scheduling, 'ico' public variables feeding hidden state reads\s+(\d+)", 2)

test.passes()
