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
test.top_filename = "t/t_constraint_solve_before_array.v"

# cvc5 does not take back its own model of a whole array, so arrays solved before
# others are pinned element by element
if not shutil.which('cvc5'):
    test.skip("No cvc5 installed")

test.compile()

test.execute(run_env='VERILATOR_SOLVER="cvc5 --incremental"')

test.passes()
