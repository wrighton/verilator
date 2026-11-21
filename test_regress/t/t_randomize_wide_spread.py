#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.timeout(60)

test.compile()

solver_log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

# Spreading is bounded: at most 512 checks plus the base and final ones per randomize(),
# and few in total (Picked alone takes thousands when split without bound)
checks = 0
total = 0
with open(solver_log, encoding="utf8") as fh:
    for line in fh:
        if line.startswith("  (check-sat"):
            checks += 1
            total += 1
        elif line.startswith("  (reset)"):
            if checks > 514:
                test.error("Too many solver checks in one randomize(): " + str(checks))
            checks = 0
if total > 2000:
    test.error("Too many solver checks: " + str(total))

# The phased solve must not have solver commands rejected
test.file_grep_not(test.run_log_filename, r'%Warning')

test.passes()
