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

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

test.execute()

# A variable named like an assumption literal makes the solver reject the query
test.file_grep_not(test.run_log_filename, r'Solver did not answer')
# Also with a variable named like the names of constraints in the unsat core query
test.file_grep(test.run_log_filename, r"Unsatisfied constraint: 'cons0 > 10;'")

test.passes()
