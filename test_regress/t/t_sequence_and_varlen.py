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
test.sim_time = 5000

test.compile(verilator_flags2=['--assert --timing --coverage-user --stats'])

test.execute()

test.file_grep(test.stats, r'Assertions, NFA per-attempt properties\s+(\d+)', 16)
test.file_grep(test.stats, r'Assertions, NFA per-attempt properties over width limit\s+(\d+)', 1)
# The state of a delay range after a first operand of fixed length is one vector
test.file_grep(test.stats, r'Assertions, NFA per-attempt register bits\s+(\d+)', 702)

test.passes()
