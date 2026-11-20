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

# Each process awaits the edge of its own bit, or its own event sharing an edge with half of the
# others, so verilation must scale linearly with their number.
SIZE_RATIO = 4
SIZE_SMALL = 400
SIZE_LARGE = SIZE_SMALL * SIZE_RATIO
RATIO_MIN = 3
RATIO_MAX = 6  # Linear scaling gives 4x, quadratic gives 16x


# Returns the number of assignments and of method calls in the written model
def verilation(size, **kwargs):
    test.compile(timing_loop=True,
                 verilator_flags2=["--timing", "--stats", "-GSize=" + str(size)],
                 **kwargs)
    counts = []
    for node in ("ASSIGN", "CMETHODHARD"):
        found = re.search(r'Node count, ' + node + r' .*\s(\d+)\s+\d+\n',
                          test.file_contents(test.stats))
        if not found:
            test.error(node + " count not found in " + test.stats)
        counts.append(int(found.group(1)))
    return counts


small = verilation(SIZE_SMALL)
test.execute()
large = verilation(SIZE_LARGE, verilator_make_gmake=False)

for small_count, large_count in zip(small, large):
    ratio = large_count / small_count
    if not RATIO_MIN <= ratio <= RATIO_MAX:
        test.error(f"Written nodes scaled by {ratio:.3f} ({small_count} to {large_count}), " +
                   f"expected {RATIO_MIN}..{RATIO_MAX}")

test.passes()
