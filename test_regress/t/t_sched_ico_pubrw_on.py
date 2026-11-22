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
test.top_filename = "t/t_sched_ico_pubrw.v"
test.pli_filename = "t/t_sched_ico_pubrw.cpp"

# With --vpi, it also enables input change detection
test.compile(make_top_shell=False,
             make_main=False,
             verilator_flags2=[
                 "--exe", "--vpi", "--assert", "--timing", "--stats", "-fico-public-change-detect",
                 test.pli_filename, "-CFLAGS -DTEST_IN_EVERY=0", "-CFLAGS -DTEST_PUB_DETECT=1"
             ],
             threads=(2 if test.vltmt else 1))

test.execute()

# The top level inputs, other than the four feeding C++ code that is not pure or the command line
test.file_grep(test.stats, r"Scheduling, 'ico' change detect triggers\s+(\d+)", 3)
test.file_grep(test.stats, r"Scheduling, 'ico' inputs feeding hidden state reads\s+(\d+)", 4)
# The twenty public variables read, other than ports, forced ones and those feeding hidden state
# reads, the module copies of the three public top level ports, and the force enable and value of
# the forceable variable
test.file_grep(test.stats, r"Scheduling, 'ico' public variable change detects\s+(\d+)", 25)
# The $time and the $realtime read by the logic, and the time in the assertion reports
test.file_grep(test.stats, r"Scheduling, 'ico' time reads change detected\s+(\d+)", 3)
# The two read, directly or through other logic, by C++ code that is not pure, the one pushed to a
# queue, the ones drawing random numbers, reading the command line and formatting the time, the
# ones read with a member of an object, with an object formatted and with a static member of a
# class, the one written to a file, the ones checked by assertions with actions, immediate,
# deferred, writing to a file, calling C++ code and releasing a force, and the one read with
# whether an event was triggered
test.file_grep(test.stats,
               r"Scheduling, 'ico' public variables feeding hidden state reads\s+(\d+)", 17)

# Documented difference with change detection: an assertion is reported when its logic runs, when
# its input changed or, if it reads the time, the time advanced, rather than in each evaluation
test.file_grep_count(test.run_log_filename, r"pubOneHot is not one-hot", 2)
test.file_grep_count(test.run_log_filename, r"pubOneHotImm is not one-hot", 2)
test.file_grep_count(test.run_log_filename, r"pubOneHotNoTime is not one-hot", 1)

# Written in each evaluation it was enabled for
test.file_grep(test.obj_dir + "/ico_bytes.out", r"^XX$")
test.file_grep(test.obj_dir + "/ico_defer_file.out", r"^XX$")

test.passes()
