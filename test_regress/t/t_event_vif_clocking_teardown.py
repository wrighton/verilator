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
test.pli_filename = "t/t_event_class_queue_teardown.cpp"

flags = ["--exe", "--timing", "--stats", test.pli_filename]
if test.vltmt:
    # A $finish in a parallel MTask is only pending until the end of the evaluation
    test.enable_tsan()
    flags += ["--no-threads-coarsen", "-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"]

test.compile(make_main=False, verilator_flags2=flags, threads=(2 if test.vltmt else 1))

test.execute()

test.file_grep(test.stats, r'Timing, event controls on interface events through handles\s+(\d+)',
               1)

test.passes()
