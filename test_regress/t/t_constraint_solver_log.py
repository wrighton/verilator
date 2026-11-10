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

test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

test.file_grep(solver_log, '# Verilator solver log')
# Without array variables the solver gets QF_BV, which z3 solves incrementally faster
test.file_grep(solver_log, r'\(set-logic QF_BV\)')

# Each command and reply is logged whole, however the pipe split it
longest = 0
with open(solver_log, encoding="utf8") as fh:
    for line in fh:
        if line.startswith(("  (assert", "< ((")):
            longest = max(longest, len(line))
            if line.count("(") != line.count(")"):
                test.error("Solver log breaks a line: " + line[:60])
if longest <= 4096:
    test.error("No logged line is longer than a pipe buffer")

test.passes()
