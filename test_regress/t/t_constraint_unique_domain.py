#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os

import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

test.execute()

# Uniqueness constraints with more elements than values fail without asking a solver
solver_log = test.obj_dir + "/solver_short.log"
if os.path.exists(solver_log):
    os.unlink(solver_log)
test.execute(all_run_flags=['+short', '+verilator+solver+file+' + solver_log],
             logfile=test.obj_dir + "/sim_short.log",
             expect_filename=test.golden_filename)
if os.path.exists(solver_log):
    with open(solver_log, encoding="utf8") as fh:
        if "(check-sat" in fh.read():
            test.error("Solver asked to check a uniqueness constraint short of values")

test.passes()
