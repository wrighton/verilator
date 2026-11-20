#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.scenarios('vlt')

# Each process awaits its own trigger. Its before-trigger function must compute only the trigger
# words it reads, so the function does not grow with the index of the trigger.
SIZE_RATIO = 4
SIZE_SMALL = 400
SIZE_LARGE = SIZE_SMALL * SIZE_RATIO
RATIO_MIN = 3
RATIO_MAX = 6  # Linear scaling gives 4x, quadratic gives 16x


# Returns the size of the initial evaluation when scheduled. Not --binary, so can verilate the
# large size without building it.
def verilation(size, **kwargs):
    test.compile(
        verilator_flags2=["--exe", "--main", "--timing", "--stats", "-GSize=" + str(size)],
        **kwargs)
    found = re.search(r"Size of eval, instr - 'initial', sched\s+(\d+)",
                      test.file_contents(test.stats))
    if not found:
        test.error("Initial evaluation size not found in " + test.stats)
    return int(found.group(1))


small = verilation(SIZE_SMALL)
test.execute()
large = verilation(SIZE_LARGE, verilator_make_gmake=False)

ratio = large / small
if not RATIO_MIN <= ratio <= RATIO_MAX:
    test.error(f"Initial evaluation size scaled by {ratio:.3f} ({small} to {large}), " +
               f"expected {RATIO_MIN}..{RATIO_MAX}")

test.passes()
