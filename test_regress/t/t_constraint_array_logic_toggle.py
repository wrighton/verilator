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
    test.skip("No constraint solver installed")

test.compile(threads=2 if test.vltmt else -1)
solver_log = test.obj_dir + '/solver.log'
test.execute(check_finished=True, all_run_flags=['+verilator+solver+file+' + solver_log])
# The active arrays use QF_ABV before and after the held associative array's constant-array
# solve; the held fixed-size array alone needs no constant array, read as a lookup of its values
test.file_grep(
    solver_log, r'(?s)\(set-logic QF_ABV\)(?:(?!\(reset\)).)*\(assert '
    r'.*?\(set-logic ALL\)(?:(?!\(reset\)).)*\(as const \(Array '
    r'.*?\(set-logic QF_ABV\)(?:(?!\(reset\)).)*\(let \(\(\?i '
    r'.*?\(set-logic QF_ABV\)(?:(?!\(reset\)).)*\(assert ')
test.file_grep_not(solver_log,
                   r'(?s)\(set-logic (?!ALL\))[^)]*\)(?:(?!\(reset\)).)*\(as const \(Array ')

test.passes()
