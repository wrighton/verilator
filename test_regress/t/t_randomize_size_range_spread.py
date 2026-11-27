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

test.compile()

test.execute()

# Without its range, the spreading of a size leaves the values that conflict with it to the
# solver's choice: cvc5 chose the smallest more than half the time
if shutil.which('cvc5'):
    test.execute(run_env='VERILATOR_SOLVER="cvc5 --incremental"',
                 logfile=test.obj_dir + "/vlt_sim_cvc5.log")

test.passes()
