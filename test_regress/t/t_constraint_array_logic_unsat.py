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
# Every hard constraint in each core is necessary; their report order is arbitrary.
test.files_identical_sorted(test.run_log_filename, test.golden_filename, is_logfile=True)
test.file_grep(
    solver_log, r'(?s)\(set-option :produce-unsat-cores true\)\s+\(set-logic ALL\)'
    r'(?:(?!\(reset\)).)*\(as const \(Array (?:(?!\(reset\)).)*:named __Vcons')
# The soft-only constructor needs ALL in its initial solve, not in its hard-only replay.
test.file_grep(
    solver_log, r'(?s)\(set-option :produce-unsat-assumptions true\)(?:(?!\(reset\)).)*'
    r'\(set-logic ALL\)(?:(?!\(reset\)).)*soft_v'
    r'(?:(?!\(reset\)).)*\(as const \(Array ')
test.file_grep(
    solver_log, r'(?s)\(set-option :produce-unsat-cores true\)\s+\(set-logic QF_ABV\)'
    r'(?:(?!\(reset\)).)*soft_v(?:(?!\(reset\)).)*:named __Vcons')

test.passes()
