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

solver_log = test.obj_dir + "/solver.log"

test.execute(
    all_run_flags=['+verilator+rand+sampler+default', '+verilator+solver+file+' + solver_log])

test.file_grep(solver_log, '# Verilator solver log')

# Each command and reply is logged whole on its own line, however buffers split it
test.file_grep(solver_log, r'^# Open: \S+\n  ; sampler: default$')
test.file_grep(solver_log, r'^  \(assert .* w #b0{19999}\)+$')
test.file_grep(solver_log, r'^< \(\(w #b[01]{19999}\)\)$')
# The default sampler pins each bit of w once
test.file_grep_count(solver_log,
                     r'^  \(assert \(= a\d+ \(= \(\(_ extract \d+ \d+\) w\) #b[01]\)\)\)$', 19999)
test.file_grep(solver_log, r'^  \(reset\)\n\Z')

test.passes()
