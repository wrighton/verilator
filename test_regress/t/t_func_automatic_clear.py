#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2025 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(timing_loop=True, verilator_flags2=["--stats", "--timing"])

test.execute()

if test.vlt_all:
    test.file_grep(test.stats, r'Tasks, Automatic variables local to functions\s+(\d+)', 41)
    test.file_grep(test.stats, r'Optimizations, Vars localized to C\+\+ scopes\s+(\d+)', 28)
    test.file_grep(test.stats, r'Optimizations, C\+\+ scopes made for localized vars\s+(\d+)', 4)
    test.file_grep(test.stats, r'Tasks, Automatic variable resets moved into branches\s+(\d+)', 9)

test.passes()
