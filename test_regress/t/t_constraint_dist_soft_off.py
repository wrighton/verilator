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

if not test.have_solver:
    test.skip('No constraint solver installed')

test.compile(verilator_flags2=['--stats', '-fno-constraint-fast'])

# The soft DIST could take a weighted draw, but its constraint is disabled.
test.file_grep(test.stats, r'Constraint DIST, Independent sites\s+(\d+)', 1)

solver_log = test.obj_dir + '/solver.log'
test.execute(
    all_run_flags=['+verilator+rand+sampler+default', '+verilator+solver+file+' + solver_log])

# Without a registered draw, repeated calls use the UniGen2 hashes, as with no DIST.
test.file_grep(solver_log, r'\(bvxor\s')

test.passes()
