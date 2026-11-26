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
test.top_filename = "t/t_constraint_solve_before.v"

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

# The parts of elements solved before others still answer the terms asked, whose indices
# are in hex, with every bit-vector literal of the replies in binary, as cvc5 writes them,
# and with each token of a reply on its own line, as a solver may wrap a long one
for mode in ("bin_literals", "multiline"):
    test.execute(run_env='VERILATOR_SOLVER="' + test.t_dir +
                 '/randomize_solver_tamper.py" TAMPER=' + mode)

test.passes()
