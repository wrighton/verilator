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

test.compile(verilator_flags2=['--assert --timing --stats'])

test.execute()

test.file_grep(test.stats, r'Assertions, NFA per-attempt properties\s+(\d+)', 11)

# A branch for each length of a match of the antecedent, but those no match has
test.file_grep(test.stats, r'Assertions, NFA per-attempt antecedent length branches\s+(\d+)', 25)
test.file_grep(test.stats, r'Assertions, NFA per-attempt antecedent lengths folded\s+(\d+)', 1)

test.passes()
