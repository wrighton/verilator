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

test.scenarios('vlt', 'vltmt')
if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile(threads=2 if test.vltmt else -1)
solver_log = test.obj_dir + '/solver.log'
test.execute(check_finished=True, all_run_flags=['+verilator+solver+file+' + solver_log])

# The terms of a select four deep are at most four times those of one, not twice those of
# the select below it at each depth
ites = {}
with open(solver_log, 'r', encoding='utf8') as fh:
    for line in fh:
        for name in ('yone', 'yfour', 'zone', 'zfour'):
            if line.lstrip().startswith('(assert') and re.search(r'[ (]' + name + r'[ )]', line):
                ites[name] = max(ites.get(name, 0), line.count('(ite '))
for one, four in (('yone', 'yfour'), ('zone', 'zfour')):
    if one not in ites or four not in ites:
        test.error("Constraints not found in " + solver_log)
    elif ites[four] > 4 * ites[one]:
        test.error("Select four deep has " + str(ites[four]) + " ite terms, over four times the " +
                   str(ites[one]) + " of one deep")

test.passes()
