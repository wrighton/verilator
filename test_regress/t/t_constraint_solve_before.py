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

test.compile()

solver_log = test.obj_dir + "/solver.log"

# The golden has the warnings of the Verilator-only circular orderings
if test.vlt_all:
    test.execute(all_run_flags=['+verilator+solver+file+' + solver_log],
                 expect_filename=test.golden_filename)
else:
    test.execute()

# Test 5, nested select: with j = 6, bit 6 of pa2 is solved first
if test.vlt_all:
    test.file_grep(solver_log, r'\(get-value \(\(\(_ extract 6 6\) pa2\) \)\)')

# Test 6: the bits not after mz, of mx only, are solved with mz, then the parts after mz, with
# all of ma, which has a part after mz
if test.vlt_all:
    test.file_grep(solver_log, r'\(get-value \(\(\(_ extract 6 4\) mx\) mz \)\)')
    test.file_grep(
        solver_log, r'\(get-value \(\(\(_ extract 1 0\) \(select ma #x00000001\)\) '
        r'\(\(_ extract 3 0\) mx\) \(select ma #x00000000\)\(select ma #x00000001\)\)\)')

test.passes()
