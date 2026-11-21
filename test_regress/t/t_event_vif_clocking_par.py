#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

flags = ["--binary", "--stats"]
if test.vltmt:
    # Races between the MTasks are only detected reliably by ThreadSanitizer. Keep the MTasks
    # separate, and run them on the threads however little work they hold.
    test.enable_tsan()
    flags += ["--no-threads-coarsen", "-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"]

test.compile(verilator_flags2=flags, threads=(2 if test.vltmt else 1))

test.execute()

if test.vlt_all:
    test.file_grep(test.stats,
                   r'Timing, event controls on interface events through handles\s+(\d+)', 1)
if test.vltmt:
    # Only the MTask killing processes runs alone, not the one writing a handle
    test.file_grep(test.stats, r'Scheduling, MTasks with process control\s+(\d+)', 1)

test.passes()
