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

test.execute()

if test.vlt_all:
    # Only a class without class constraints whose randomization reaches a randc variable
    # gets a generator for its randc cycles
    for name in ["RandcNone", "RandcTop"]:
        test.file_grep_any(test.glob_some(test.obj_dir + "/*" + name + "*.h"), r'__Vrandc_history')
    for name in ["RandNone", "RandChainA", "RandChainB", "RandChainC"]:
        for filename in test.glob_some(test.obj_dir + "/*" + name + "*.h"):
            test.file_grep_not(filename, r'__Vrandc_history')

test.passes()
