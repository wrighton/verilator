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
# values kept so far again, so they are not lost.
limit = 0
cut = False  # A check was cut short, and its closing is not checked yet
closing = []  # Commands and statuses since then
with open(solver_log, encoding="utf8") as fh:
    for line in fh:
        line = line.rstrip('\n')
        if line.startswith('  (set-option :reproducible-resource-limit '):
            limit = int(line.split()[-1].rstrip(')'))
        elif line.startswith('  (reset)'):
            limit = 0
        elif line.startswith('  (check-sat)') and limit:
            test.error("Main check under a resource limit: " + line)
        if cut and (line.startswith('  (') or line.startswith('< ')):
            closing.append(line)
            if len(closing) == 3:
                if (closing[0] != '  (set-option :reproducible-resource-limit 0)'
                        or not closing[1].startswith('  (check-sat-assuming')
                        or closing[2] != '< sat'):
                    test.error("Spreading cut short is not closed unlimited: " + str(closing))
                cut = False
        if line == '< unknown':
            if not limit:
                test.error("Unlimited check answered unknown")
            cut = True
            closing = []

test.passes()
