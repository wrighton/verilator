#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2024 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

# A one-hot count is a few nodes rather than a sum over each bit of the operand
cpp_bytes = sum(os.path.getsize(f) for f in test.glob_some(test.obj_dir + "/*.cpp"))
if cpp_bytes > 200000:
    test.error("Generated C++ is " + str(cpp_bytes) + " bytes")

test.execute()

test.passes()
