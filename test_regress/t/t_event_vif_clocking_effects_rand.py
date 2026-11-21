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
test.top_filename = "t/t_event_vif_clocking_effects.v"

flags = ["--binary", "--stats", "+define+T_RAND"]
if test.vlt_all:
    flags += ["--debugi-V3Timing", "4"]
test.compile(verilator_flags2=flags)

test.execute()

if test.vlt_all:
    test.file_grep(test.stats,
                   r'Timing, event controls on interface events through handles\s+(\d+)', 0)
    test.file_grep(test.stats,
                   r"Timing, event controls through handles with 'iff' effects\s+(\d+)", 2)
    test.file_grep(test.compile_log_filename, r"Polled, 'iff' with effects, wait at")

test.passes()
