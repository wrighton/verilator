#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vltmt')

# The hand-off between the threads dumping in parallel, when the thread
# committing the buffers suspends, races only rarely,
# use ThreadSanitizer to test
test.enable_tsan()

test.top_filename = "t/t_trace_threads_tsan.v"

# Spin once only, so the dumping thread suspends
test.compile(verilator_flags2=['--binary', '--trace-vcd', '-CFLAGS -DVL_LOCK_SPINS=1'], threads=2)

test.execute()

test.passes()
