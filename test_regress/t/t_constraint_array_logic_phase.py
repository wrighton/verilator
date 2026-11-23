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
test.execute(
    check_finished=True,
    all_run_flags=['+verilator+solver+file+' + solver_log, '+verilator+rand+sampler+default'])
# The 4-bit state array uses ALL in the scalar solve-before session.
test.file_grep(
    solver_log, r'(?s)\(set-logic ALL\)(?:(?!\(reset\)).)*'
    r'\(as const \(Array \(_ BitVec 32\) \(_ BitVec 4\)\)')
# A soft-only 5-bit state array uses ALL; a plain scalar phased solve keeps QF_ABV.
test.file_grep(
    solver_log, r'(?s)\(set-logic ALL\)(?:(?!\(reset\)).)*'
    r'\(declare-fun soft_v (?:(?!\(reset\)).)*'
    r'\(as const \(Array \(_ BitVec 32\) \(_ BitVec 5\)\)')
test.file_grep(solver_log, r'(?s)\(set-logic QF_ABV\)(?:(?!\(reset\)).)*\(declare-fun plain_v ')
# Repeated default sampling reaches a constructor-bearing UniGen2 transaction.
test.file_grep(
    solver_log, r'(?s)\(set-option :produce-models true\)'
    r'(?:(?!\(reset\)|:produce-unsat-assumptions).)*'
    r'\(set-logic ALL\)(?:(?!\(reset\)).)*'
    r'\(as const \(Array \(_ BitVec 32\) \(_ BitVec 7\)\)')
test.file_grep_not(solver_log,
                   r'(?s)\(set-logic (?!ALL\))[^)]*\)(?:(?!\(reset\)).)*\(as const \(Array ')

test.passes()
