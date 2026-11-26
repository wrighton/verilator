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

solver_log = test.obj_dir + "/solver.log"

test.compile()

test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

with open(solver_log, encoding="utf8") as fh:
    sessions = fh.read().split("\n  (reset)\n")

# A size solve declares the size without the final solve's pin of it; after the first
# call it also holds the elements of the old size, which it neither pins nor asks
# An element is a select of the array, or with d read only by element, a constant of its own
elements = ("(select d ", " d__Vs", "(d__Vs")
stale = 0
for text in sessions:
    if "(declare-fun __Vd_size " not in text or "(= __Vd_size (_ bv" in text:
        continue
    if "(select d #x" in text or "(declare-fun d__Vs" in text:
        stale += 1
    for line in text.split("\n"):
        if (line.startswith("  (assert (= __Va") or line.startswith("  (get-value")) and any(
                element in line for element in elements):
            test.error("Size solve pins or asks an element: " + line[:200])
if stale < 10:
    test.error("Size solves holding elements of the old size: " + str(stale))
# Each call ties n first to a value of its range, which the size takes without a conflict to
# split, so spreading takes few checks (363 with z3 4.13 to 5.4 and cvc5; 724 or more, 1019
# with cvc5, tying n to any value)
checks = sum(text.count("\n  (check-sat") for text in sessions)
if checks > 450:
    test.error("Solver checks: " + str(checks))

# The sizes the solver's own models would take differ, the distribution must not
if shutil.which('cvc5'):
    test.execute(run_env='VERILATOR_SOLVER="cvc5 --incremental"')

test.passes()
