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
    test.skip("No constraint solver installed")

test.compile()

solver_log = test.obj_dir + "/solver.log"

test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

test.file_grep(solver_log, '# Verilator solver log')

# Without array variables the solver gets QF_BV, which z3 solves incrementally faster,
# unless two variables are multiplied, which z3 solves faster with QF_ABV. A session
# is found by the first variable it declares.
session = r'^  \(set-logic (\S+)\)\n(?:  \(define-fun .*\n)*  \(declare-fun '
test.file_grep(solver_log, session + r'tripled ', 'QF_BV')
test.file_grep(solver_log, session + r'factor_a ', 'QF_ABV')

test.passes()
