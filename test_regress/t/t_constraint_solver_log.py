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

test.execute(
    all_run_flags=['+verilator+rand+sampler+default', '+verilator+solver+file+' + solver_log])

test.file_grep(solver_log, '# Verilator solver log')
# Without array variables the solver gets QF_BV, which z3 solves incrementally faster
test.file_grep(solver_log, r'\(set-logic QF_BV\)')
# Each operator over one element is just that element's term, never the operator
# applied to that term alone
term = r'\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)'
test.file_grep_not(solver_log, r'\((?:bvadd|bvand|bvmul|bvor|bvxor) +' + term + r'\)')
# Each collapsed form appears as the bare element term
test.file_grep(solver_log, r'\(assert \(= #b1 +\(__Vbv \(= #b0010001 x\)\)\)\)')
test.file_grep(solver_log, r'\(__Vbv \(not \(__Vbool +\(__Vbv \(= #b0010001 y\)\)\)\)\)')
for name, value in (('sum_a', '0001001'), ('prod_a', '0001010'), ('and_a', '0001011'),
                    ('or_a', '0001100'), ('xor_a', '0001101')):
    test.file_grep(solver_log,
                   r'\(__Vbv \(= +\(select ' + name + r' #x00000000\) #b' + value + r'\)\)')
test.file_grep(solver_log, r'\(__Vbool +\(__Vbv \(= \(select fixed #x00000000\) #b0000101\)\)\)')
test.file_grep(
    solver_log,
    r'\(__Vbool +\(__Vbv \(= \(select \(select grid #x00000000\) #x00000000\) #b0000110\)\)\)')

# The solver log is the output under test: each command and reply is one whole line
test.file_grep(solver_log, r'^# Open: \S+\n  ; sampler: default$')
test.file_grep(solver_log, r'^  \(assert .* w #b0{19999}\)+$')
test.file_grep(solver_log, r'^< \(\(w #b[01]{19999}\)\)$')
# One whole command per bit of w
test.file_grep_count(solver_log,
                     r'^  \(assert \(= __Va\d+ \(= \(\(_ extract \d+ \d+\) w\) #b[01]\)\)\)$',
                     19999)
test.file_grep(solver_log, r'^  \(reset\)\n\Z')

test.passes()
