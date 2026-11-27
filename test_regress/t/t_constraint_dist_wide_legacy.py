#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt', 'vltmt')

if not test.have_solver:
    test.skip('No constraint solver installed')

test.compile(verilator_flags2=['--binary', '--stats', '-fno-constraint-fast'])

# Oversized targets and items, zero-weight items with random operands or excluded
# ranges (including all-zero sites), sites over the item cap, and classes with random
# array sizes keep procedural weighting.
test.file_grep_not(test.stats, r'Constraint DIST, Independent sites')

test.execute(all_run_flags=['+verilator+rand+sampler+solver'])

test.passes()
