#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re
import shutil
import vltest_bootstrap

test.scenarios('simulator')

if not test.have_solver:
    test.skip("No constraint solver installed")
if not shutil.which('z3'):
    test.skip("No z3 installed")

test.compile()

solver_log = test.obj_dir + "/solver.log"

test.execute(run_env='VERILATOR_SOLVER="z3 --in"',
             all_run_flags=['+verilator+solver+file+' + solver_log])

# A queue or dynamic array of random size solved before other variables is pinned for the
# later phases element by element, up to the size read from its size variable, never by
# the solver's model of the whole array. The runtime finds the size variable by the name
# the compiler gives it (V3SolverSmt sizeVarName), so this fails if the two drift apart.
test.file_grep(solver_log, r'^  \(get-value \(__V\w+_size ')
# The size read last before a pin of it, after its phase's diversity check, is the value
# pinned with the elements
with open(solver_log, encoding="utf8") as fh:
    text = fh.read()
last = {}  # Size variable -> value read last
pinned = 0
for m in re.finditer(
        r'^  \(get-value \((__V\w+_size) \)\)\n< \(\(\1 (#[bx][0-9a-f]+)\)\)$|'
        r'^  \(assert \(= (__V\w+_size) (#[bx][0-9a-f]+)\)\)$', text, re.M):
    if m.group(1):
        last[m.group(1)] = m.group(2)
    elif m.group(3) in last:
        pinned += 1
        if m.group(4) != last.pop(m.group(3)):
            test.error("Size pinned is not the one read last: " + m.group(0))
if not pinned:
    test.error("No size read was pinned")
test.file_grep_not(solver_log, r'^  \(assert \(= \w+ \((store|\(as const)')
# Arrays of size 0 leave nothing to ask for
test.file_grep_not(solver_log, r'^  \(get-value \(\)\)')

# cvc5 does not take back a solver's model of a whole array, the reason for pinning by element
if shutil.which('cvc5'):
    test.execute(run_env='VERILATOR_SOLVER="cvc5 --incremental"')

test.passes()
