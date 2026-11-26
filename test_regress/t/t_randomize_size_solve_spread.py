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

solver_log = test.obj_dir + "/solver.log"

test.compile()

test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])

with open(solver_log, encoding="utf8") as fh:
    sessions = fh.read().split("\n  (reset)\n")

# A size solve declares the size without the final solve's pin of it; after the first
# call it also holds the elements of the old size, which it neither pins nor asks
stale = 0
for text in sessions:
    if "(declare-fun __Vd_size " not in text or "(= __Vd_size (_ bv" in text:
        continue
    if "(select d #x" in text:
        stale += 1
    for line in text.split("\n"):
        if (line.startswith("  (assert (= __Va")
                or line.startswith("  (get-value")) and "(select d " in line:
            test.error("Size solve pins or asks an element: " + line[:200])
if stale < 10:
    test.error("Size solves holding elements of the old size: " + str(stale))

test.passes()
