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

# The text of the constraints and their tables in a solver session is linear in the number
# of reads, N = 40, of the N-element table; each copy of the table would add about 1100 bytes
limit = 40 * 300
with open(solver_log, 'r', encoding='utf8') as fh:
    session = 0
    for line in fh:
        if '(set-logic' in line:
            session = 0
        elif line.lstrip().startswith(('(assert (= #b1', '(define-fun __Vt')):
            session += len(line)
            if session > limit:
                test.error("Solver session text over " + str(limit) + " bytes")
test.file_grep(solver_log, r'\(define-fun __Vt\d+ \(\(\?i \(_ BitVec 32\)\)\) \(_ BitVec 16\) ')

test.passes()
