#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import shutil
import vltest_bootstrap

test.scenarios('vlt')
test.top_filename = "t/t_constraint_array_logic_toggle.v"

# cvc5 takes constant arrays only with its experimental arrays solver, which it is given before
# each logic for them
if not shutil.which('cvc5'):
    test.skip("No cvc5 installed")

test.compile()
solver_log = test.obj_dir + '/solver.log'
test.execute(check_finished=True,
             all_run_flags=['+verilator+solver+file+' + solver_log],
             run_env='VERILATOR_SOLVER="cvc5 --incremental"')
test.file_grep(solver_log, r'\(set-option :arrays-exp true\)\n  \(set-logic ALL\)')
test.file_grep_not(solver_log, r'(?<!\(set-option :arrays-exp true\)\n)  \(set-logic ALL\)')

test.passes()
