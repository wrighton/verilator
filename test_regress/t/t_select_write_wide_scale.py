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

if test.have_dev_gcov:
    test.skip("Too slow with code coverage")
if test.have_dev_asan or test.tsan:
    test.skip("Too slow with sanitizers")

# Streaming a structure of N 64-bit words into a vector assigns its parts to constant selects of
# the vector. Checks the operation count of every stage; the model is not built.
SIZE_RATIO = 4
SIZE_SMALL = 256
SIZE_LARGE = SIZE_SMALL * SIZE_RATIO
RATIO_MIN = 3
RATIO_MAX = 8  # Linear scaling gives 4x, quadratic gives 16x


def verilation(n):
    test.compile(verilator_flags2=[
        "--stats", "--debug", "--debugi 0", "--no-debug-check", "--no-dump-tree", "-GN=" + str(n)
    ],
                 make_main=False,
                 verilator_make_gmake=False)
    return test.op_count_read(test.stats)


test.op_count_ok(verilation(SIZE_SMALL), verilation(SIZE_LARGE), RATIO_MIN, RATIO_MAX, r'.*')

test.passes()
