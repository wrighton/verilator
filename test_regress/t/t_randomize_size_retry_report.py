#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile(verilator_flags2=['--binary'])

# The solver's model is the random result, so the statuses are in a fixed order. Status 1
# answers the session's opening check-sat; 2 and 3 the size solve and the solve of the
# elements of the first try; 4 and 5 those of the second, whose element solve the solver
# answers unknown, which is not an unsatisfied solve
tamper = 'VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" TAMPER_AT=5 '

# The constraints set up again are unsatisfied, so those are reported
logfile = test.obj_dir + '/sim_core.log'
test.execute(logfile=logfile,
             all_run_flags=['+verilator+rand+sampler+solver'],
             run_env=tamper + 'TAMPER=unknown_once')
test.file_grep(logfile, r"Unsatisfied constraint: 'foreach \(q\[i\]\) if \(i == 2\) \{'")

# The solver answers that setup unknown too, so the failure is reported
logfile = test.obj_dir + '/sim_failed.log'
test.execute(logfile=logfile,
             all_run_flags=['+verilator+rand+sampler+solver'],
             run_env=tamper + 'TAMPER=unknown_twice')
test.file_grep(
    logfile, r'UNSATCONSTR: randomize\(\) failed after trying sizes whose unsatisfied '
    r'constraints were not reported\.')

test.passes()
