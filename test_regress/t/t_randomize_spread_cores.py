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

test.compile()

test.execute()


def checks(log):
    with open(log, encoding="utf8") as fh:
        return len(re.findall(r'^  \(check-sat', fh.read(), re.M))


tamper = 'VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" TAMPER='
# Every literal assumed in each core, as a solver may give: narrowed down as with cvc5
# (852 checks for the 5 calls)
solver_log = test.obj_dir + "/solver_wide.log"
test.execute(run_env=tamper + 'wide_core', all_run_flags=['+verilator+solver+file+' + solver_log])
if checks(solver_log) > 1000:
    test.error("Solver checks with wide cores: " + str(checks(solver_log)))
# A check of the narrowing cut short ends the spreading, and the call still passes
test.execute(run_env=tamper + 'wide_core_cut', all_run_flags=['+cut'])

# cvc5 names most of the ties checked in each unsat core: they are narrowed down, in a
# bounded number of checks (529 for the 5 calls; 608 without narrowing, 345 with z3)
if shutil.which('cvc5'):
    solver_log = test.obj_dir + "/solver_cvc5.log"
    test.execute(run_env='VERILATOR_SOLVER="cvc5 --incremental"',
                 all_run_flags=['+verilator+solver+file+' + solver_log])
    if checks(solver_log) > 700:
        test.error("Solver checks: " + str(checks(solver_log)))

test.passes()
