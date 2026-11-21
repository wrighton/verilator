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

# Verilator samples, so results vary
log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=[
    '+verilator+rand+sampler+default', '+check_varied', '+verilator+solver+file+' + log
])
test.file_grep(log, r'; sampler: default')
# The solver accepts every command, so no runtime-declared name clashes with a variable
test.file_grep_not(log, r'\(error')
# The UniGen2 diversification literals that d0 is named after are declared
test.file_grep(log, r'\(declare-fun __Vd0 ')
# ScalarAndEmpty's s is still enumerated: UniGen2 excludes each witness it finds
test.file_grep(log, r'^  \(assert \(not (?:\(and )?\(= s +#b[01]+\)\)?\)\)$')
# Nothing to enumerate leaves no empty get-value or connective for the solver
test.file_grep_not(log, r'\(get-value \( *\)\)')
test.file_grep_not(log, r'\((?:and|or) *\)')
# UniGen2 excludes each witness found: one equality alone, as SMT-LIB 'and' takes at least
# two operands, or one equality per element under 'and'
test.file_grep(log, r'^  \(assert \(not \(= v +#b[01]+\)\)\)$')
test.file_grep(log, r'^  \(assert \(not \(and \(= a0 +#b[01]+\) \(= b +#b[01]+\)\)\)\)$')
test.file_grep(
    log, r'^  \(assert \(not \(and \(= \(select d0 #x00000000\) +#b[01]+\)'
    r' \(= \(select d0 #x00000001\) +#b[01]+\) \(= \(select d0 #x00000002\) +#b[01]+\)\)\)\)$')
term = r'\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)'
test.file_grep_not(log, r'\(and +' + term + r'\)')

# A UniGen2 hash equation selecting no bit is still an application of two operands, as
# SMT-LIB 'bvxor' takes at least two
test.file_grep(log, r'\(bvxor #b0 #b0\)')
test.file_grep_not(log, r'\(bvxor +[^ ()]+\)')

test.passes()
