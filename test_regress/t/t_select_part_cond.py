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
    # Each member of a wide element at a loop index is read from the element it is in, not from
    # the whole value below its top; only those at an index wider than its range, which may be
    # out of range, read the value padded
    test.file_grep(test.stats, r'Optimizations, Selects of selects padded\s+(\d+)', 12)

test.passes()
