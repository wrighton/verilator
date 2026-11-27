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

test.compile(verilator_flags2=['--binary'])

test.execute()

test.file_grep(
    test.run_log_filename,
    r"randomize\(\) returns 0: the constraints give 'q' \d+ elements, over the 1048576")
test.file_grep(
    test.run_log_filename,
    r"randomize\(\) returns 0: the constraints give 'a' \d+ elements, over the 1048576")

# The limit the plusarg sets is the one checked
test.execute(all_run_flags=["+verilator+rand+array+max+2", "+lowered"])

test.passes()
