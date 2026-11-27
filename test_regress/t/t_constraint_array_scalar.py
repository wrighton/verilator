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

test.compile(verilator_flags2=['--stats', '-Wno-UNSATCONSTR', '-Wno-WIDTH'])

# idx, y, fixed_a, grow, and of Last and Ordered idx, y and q; not arr of a merged object, nor
# whole and elems solved together
test.file_grep(test.stats, r'Randomize, scalarized arrays\s+(\d+)', 7)

log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + log])

# Elements are constants of their own, an index without an element too, and only the array
# read whole is an SMT array
test.file_grep(log, r'\(declare-fun idx__Vs0000000f \(\) \(_ BitVec 8\)\)')
test.file_grep(log, r'\(declare-fun fixed_a__Vs00000003 \(\) \(_ BitVec 7\)\)')
test.file_grep(log, r'\(declare-fun grow__Vg00000005 \(\) \(_ BitVec 8\)\)')
test.file_grep(log, r'\(declare-fun whole \(\) \(Array')
test.file_grep(log, r'\(declare-fun elems \(\) \(Array')
test.file_grep_not(log, r'\(declare-fun (idx|y|fixed_a|grow) \(\) \(Array')
test.file_grep_not(log, r'elems__V[sg]')
test.file_grep(log, r'\(let \(.*\(arr h\.arr\)')
# The table lookups are solved without arrays
test.file_grep(log, r'\(set-logic QF_BV\)')
# q[$] of a queue whose size is solved is the element at the solver's index
test.file_grep(log, r'\(define-fun idx__Vc00000000 \(\) \(_ BitVec 8\) \(ite ')

test.passes()
