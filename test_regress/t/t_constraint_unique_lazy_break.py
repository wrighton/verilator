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

test.compile()

# The solver dying at the spreading of every lazy round, whose fallback spreads normally: each
# call returns its solution with no warning of it, and the breaks pause the spreading of the
# object as one in the returned solution's round would, so of the 16 calls only 1, 3, 6 and 11
# spread
log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + log],
             run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
             'TAMPER=die_lazy TAMPER_EXIT=101')
test.file_grep_not(test.run_log_filename, r'Solver (died|failed)')
with open(log, encoding="utf8") as fh:
    sessions = fh.read().split("\n  (reset)\n")
spreads = sum(1 for text in sessions
              if "(distinct " not in text and "\n  (check-sat-assuming" in text)
if spreads != 4:
    test.error(str(spreads) + " lazy rounds spread, not 4")

test.passes()
