#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

# The order of the processes woken in the same evaluation, and the waiters finishing resumes,
# are rules of Verilator
test.scenarios('vlt_all')

flags = ["--binary", "--stats"]
if test.vltmt:
    # Races between the MTasks are only detected reliably by ThreadSanitizer. Keep the MTasks
    # separate, and run them on the threads however little work they hold.
    test.enable_tsan()
    flags += ["--no-threads-coarsen", "-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"]

test.compile(verilator_flags2=flags, threads=(2 if test.vltmt else 1))

test.execute()

if test.vlt_all:
    test.file_grep(test.stats, r'Timing, event controls on event wait lists\s+(\d+)', 12)
    test.file_grep(test.stats, r'Timing, event controls on wait queues\s+(\d+)', 4)
if test.vltmt:
    # The blocks that kill processes, or start them through a class task, run alone
    test.file_grep(test.stats, r'Scheduling, MTasks with process control\s+(\d+)', 3)

test.passes()
