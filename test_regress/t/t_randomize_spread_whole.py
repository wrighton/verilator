#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import shutil
import vltest_bootstrap

test.scenarios('simulator')

if not test.have_solver:
    test.skip("No constraint solver installed")
if not shutil.which('z3'):
    test.skip("No z3 installed")

test.compile()

solver_log = test.obj_dir + "/solver.log"

# The check counts are those of z3's unsat cores
test.execute(run_env='VERILATOR_SOLVER="z3 --in"',
             all_run_flags=['+verilator+solver+file+' + solver_log])

# Spreading checks of each solve, which starts its own session text
calls = []
with open(solver_log, encoding="utf8") as fh:
    for line in fh:
        if line.startswith('  (set-logic '):
            calls.append(0)
        elif line.startswith('  (check-sat-assuming') and calls:
            calls[-1] += 1
calls = [n for n in calls if n]

# Each array's size is solved first. Ones: the few elements that conflict are dropped one
# by one (16 checks with z3 4.13 to 5.4), rather than dropping every element and spreading
# all of them again part by part (25 checks). Below: still dropped for all (43 to 47 checks),
# where going one by one would take hundreds. Most: dropped for all once too many conflict
# one by one (61 checks), rather than spending every check one by one (513).
if len(calls) != 6 or calls[1] > 20 or calls[3] > 100 or calls[5] > 200:
    test.error("Spreading checks per solve: " + str(calls))

test.passes()
