#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

# That a mailbox waits for its processes testing their conditions is of Verilator
test.scenarios('vlt_all')
test.top_filename = "t/t_mailbox_wait_gate.v"

test.compile(verilator_flags2=["--binary", "--stats", "+define+T_GATE_VIRTUAL"])

test.execute()

test.file_grep(test.stats, r'Timing, mailbox waits polled\s+(\d+)', 3)
test.file_grep(test.stats, r'Timing, event controls on wait queues\s+(\d+)', 0)

test.passes()
