#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

solver_log = test.obj_dir + "/solver.log"

test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

# Per randomize(), few checks rather than one per element, and at most 64 satisfied ones,
# which Wide reaches. Checks of a prefix, narrowing down a large unsat core as cvc5 gives,
# are marked in the log and count only towards the total.
most_satisfied = 0
with open(solver_log, encoding="utf8") as fh:
    for session in fh.read().split("  (reset)"):
        checks = re.findall(r'^(  ; prefix\n)?  \(check-sat-assuming.*\n(?:  .*\n)*?< (\w+)',
                            session, re.M)
        replies = [reply for prefix, reply in checks if not prefix]
        if len(replies) > 400 or len(checks) > 600:
            test.error("Too many solver checks in one randomize(): " + str(len(replies)) + " of " +
                       str(len(checks)))
        most_satisfied = max(most_satisfied, replies.count("sat"))
if most_satisfied != 64:
    test.error("Most satisfied checks in one randomize(): " + str(most_satisfied))

test.passes()
