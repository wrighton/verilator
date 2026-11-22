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

# Input change detection only: the readers of public variables run on every evaluation
test.compile(make_top_shell=False,
             make_main=False,
             verilator_flags2=[
                 "--exe", "--vpi", "--assert", "--timing", "--stats", "-fico-change-detect",
                 test.pli_filename, "-CFLAGS -DTEST_IN_EVERY=0", "-CFLAGS -DTEST_PUB_DETECT=0"
             ],
             threads=(2 if test.vltmt else 1))

test.execute()

test.file_grep(test.stats, r"Scheduling, 'ico' change detect triggers\s+(\d+)", 7)
test.file_grep_not(test.stats, r"public variable change detects")

# Reported in each evaluation
test.file_grep_count(test.run_log_filename, r"pubOneHot is not one-hot", 4)
test.file_grep_count(test.run_log_filename, r"pubOneHotImm is not one-hot", 4)
test.file_grep_count(test.run_log_filename, r"pubOneHotNoTime is not one-hot", 4)

# Written in each evaluation it was enabled for
test.file_grep(test.obj_dir + "/ico_bytes.out", r"^XX$")
test.file_grep(test.obj_dir + "/ico_defer_file.out", r"^XX$")

test.passes()
