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

# Only the final solve, of the sizes solved, asks the elements to differ
with open(solver_log, encoding="utf8") as fh:
    terms = re.findall(r'\(distinct((?: ?\(select q [^)]*\))+)\)', fh.read())
if len(terms) < 3:
    test.error("Expected a 'distinct' for each final solve, got " + str(len(terms)))
for term in terms:
    if not 18 <= term.count('(select') <= 20:
        test.error("A 'distinct' of " + str(term.count('(select')) + " elements")

test.passes()
