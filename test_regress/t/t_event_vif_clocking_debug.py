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
# The debug output says why each wait on a clocking block event through handles is not on the
# wait list of the event
test.top_filename = "t/t_event_vif_clocking.v"

test.compile(verilator_flags2=["--binary", "--debugi-V3Timing", "4"])

test.execute()

test.file_grep(
    test.compile_log_filename,
    r"Polled, 'm_dly' written other than as a whole by a blocking assignment at \S+, wait at")
test.file_grep(test.compile_log_filename, r"Polled, 's_vif' public, wait at")
test.file_grep(test.compile_log_filename, r"Polled, 'vif' a port, wait at")
test.file_grep(test.compile_log_filename, r"Polled, not through variables, wait at")
test.file_grep(test.compile_log_filename, r"Polled, not only on a clocking block event, wait at")
test.file_grep(test.compile_log_filename, r"Polled, a chain of more than 16 handles, wait at")

# Each reason names the write, not the wait, also for a write deleted as it is never reached
test.file_grep_not(test.compile_log_filename, r"at (\S+:\d+:\d+), wait at \1:")
with open(test.top_filename, encoding="utf8") as fh:
    lines = fh.read().splitlines()
dead_write = next(i for i, line in enumerate(lines) if "wait (0) m_vif = #1 ib;" in line)
dead_wait = next(i for i in range(dead_write, len(lines)) if "@(m_vif.cb);" in lines[i])
dead_reason = r"Polled, 'm_vif' written other than as a whole by a blocking assignment at "
dead_reason += rf"\S+:{dead_write + 1}:\d+, wait at \S+:{dead_wait + 1}:"
test.file_grep(test.compile_log_filename, dead_reason)

test.passes()
