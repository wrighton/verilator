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

test.compile(verilator_flags2=["--binary", "--stats"])

test.execute()

if test.vlt_all:
    test.file_grep(test.stats,
                   r'Timing, event controls on interface events through handles\s+(\d+)', 18)
    test.file_grep(test.stats, r'Timing, writes of handles notifying event controls\s+(\d+)', 60)
    test.file_grep(test.stats,
                   r'Timing, writes of handles notifying event controls if changed\s+(\d+)', 12)
    test.file_grep(test.stats,
                   r"Timing, event controls through handles with 'iff' effects\s+(\d+)", 0)
    test.file_grep(test.stats,
                   r'Timing, event controls on clocking block events evaluated always\s+(\d+)', 29)

test.passes()
