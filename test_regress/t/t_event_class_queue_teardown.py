#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

flags = ["--exe", "--timing", test.pli_filename]
if test.vltmt:
    # A $finish in a parallel MTask is only pending until the end of the evaluation
    flags += ["--no-threads-coarsen", "-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"]

test.compile(make_main=False, verilator_flags2=flags, threads=(2 if test.vltmt else 1))

test.execute()

test.passes()
