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

# The resource limit of a spreading check is calibrated in z3's units
test.execute(run_env='VERILATOR_SOLVER="z3 --in"',
             all_run_flags=['+verilator+solver+file+' + solver_log])

# A hard spreading check stops at the limit, quietly, as randomize() still succeeds
test.file_grep(solver_log, r'^< unknown$')
test.file_grep_not(test.run_log_filename, r'Solver returned unknown')

# Every main check is unlimited, also one after a limited spreading in the same randomize().
# A check cut short ends the spreading: the limit is lifted, and an unlimited check finds the
# values kept so far again, so they are not lost. With none kept, the constraints are solved
# again under the limit, and past it in a fresh session: after a (reset), one plain check,
# under a larger limit, of the constraints and random hashes, else an unlimited one (R501).
limit = 0
cut = False  # A check was cut short, and the solution is not found again yet
fresh_now = False  # In a fresh session since
fresh = 0  # Cuts closed in a fresh session
with open(solver_log, encoding="utf8") as fh:
    for line in fh:
        line = line.rstrip('\n')
        if line.startswith('  (set-option :reproducible-resource-limit '):
            limit = int(line.split()[-1].rstrip(')'))
        elif line.startswith('  (reset)'):
            limit = 0
            fresh_now = cut
        elif line.startswith('  (check-sat)') and limit and not fresh_now:
            test.error("Main check under a resource limit: " + line)
        elif line.startswith('  (check-sat-assuming (') and cut and limit:
            if line != '  (check-sat-assuming ())' or fresh_now:
                test.error("Spreading cut short is not closed unlimited: " + line)
        elif line == '< sat' and cut:
            cut = False
            fresh += fresh_now
            fresh_now = False
        elif line == '< unknown':
            if not limit:
                test.error("Unlimited check answered unknown")
            cut = True
if cut:
    test.error("Spreading cut short is not closed")
if not fresh:
    test.error("No spreading cut short with none kept was closed in a fresh session")

test.passes()
