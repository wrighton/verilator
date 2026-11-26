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
# A held element read by a random index is a lookup of its values, not an array term, except
# through two objects
test.file_grep_not(solver_log, r'\(store (?!\(|mid\.leaf\.deep )')
# Nor is the array declared, so the large table's solve needs no array logic
test.file_grep(solver_log, r'\(set-logic QF_BV\)')
test.file_grep_not(solver_log, r'declare-fun table_ ')
# Except where named
test.file_grep(solver_log, r'declare-fun mid\.leaf\.deep ')

test.passes()
