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

test.compile(verilator_flags2=['--stats'], threads=4)

test.file_grep(test.stats, r'Scheduling, virtual interface read barriers\s+(\d+)', 69)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier edges\s+(\d+)', 704)
test.file_grep(test.stats, r'Scheduling, virtual interface read barrier move edges\s+(\d+)', 704)

# Linear in the functions and members (3876 here)
steps = int(
    test.file_grep(test.stats, r'Scheduling, virtual interface read call graph steps\s+(\d+)')[0])
if steps > 6000:
    test.error("Finding virtual interface reads went quadratic: {} steps".format(steps))

test.passes()
