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

test.compile(verilator_flags2=['-fno-constraint-fast'])

log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + log])

# The first spreading check of the array ties 4096 of its 20000 elements
with open(log, encoding="utf8") as fh:
    literals = [
        len(re.findall(r'__Va\d+', line)) for line in fh
        if line.startswith('  (check-sat-assuming (')
    ]
first = next((n for n in literals if n > 1), 0)
if first != 4096:
    test.error("First spreading check ties " + str(first) + " terms, not 4096")

test.passes()
