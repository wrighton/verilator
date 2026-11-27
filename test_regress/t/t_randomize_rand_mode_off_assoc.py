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
# The keys of an array are given once per solve, however often it is read
test.file_grep(solver_log, r'\(define-fun __Vrd_aa .*\(select __Vka_aa \(select __Vrk_aa \?k\)\)')
with open(solver_log, encoding='utf8') as fh:
    log = fh.read()
definitions = log.count('(define-fun __Vrd_aa ')
keys = log.count('(assert (= (select __Vrk_aa ')
if definitions == 0 or keys > 100 * definitions:
    test.error("Keys given at each read: " + str(keys) + " keys, " + str(definitions) +
               " definitions")

test.passes()
