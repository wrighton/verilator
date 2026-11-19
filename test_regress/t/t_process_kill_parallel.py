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

flags = ["--binary", "--stats"]
if test.vltmt:
    # Unordered process control is a genuine data race, but whether it changes the results in
    # any one run depends on timing, so use ThreadSanitizer to detect it. That needs the static
    # thread assignment to put the two blocks of some pair on different threads, as it does
    # without the fix. --no-threads-coarsen keeps the blocks in separate MTasks, and a zero
    # serial cost makes them run in parallel.
    test.enable_tsan()
    flags += ["--no-threads-coarsen", "-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"]

test.compile(verilator_flags2=flags, threads=(2 if test.vltmt else 1))

test.execute()

if test.vltmt:
    # The ten blocks controlling processes, each run alone
    test.file_grep(test.stats, r'Scheduling, MTasks with process control\s+(\d+)', 10)

test.passes()
