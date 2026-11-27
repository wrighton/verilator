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

# The status of the first check keeping a size, in a run without the solver dying
log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + log])
with open(log, encoding="utf8") as fh:
    text = fh.read()
at = text[:text.index("(check-sat-assuming (__Vsz")].count("\n  (check-sat") + 1

# The solver dies there, once
latch = test.obj_dir + "/died.latch"
if os.path.exists(latch):
    os.unlink(latch)
logfile = test.obj_dir + "/sim_died.log"
test.execute(all_run_flags=['+died'],
             logfile=logfile,
             run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
             'TAMPER=die_status_at TAMPER_AT=' + str(at) + ' TAMPER_ONCE="' + latch + '" ')
test.file_grep(logfile, r'Solver died')

test.passes()
