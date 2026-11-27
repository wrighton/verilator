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

# Above the latency the per-attempt lowering takes, so the NFA lowers both sizes
SIZE_SMALL = 260
SIZE_LARGE = SIZE_SMALL * 2
MAX_RATIO = 3  # Linear growth gives 2, quadratic 4


def cloned_nodes(n):
    test.compile(verilator_flags2=['--assert', '--stats', f'-GN={n}'],
                 make_main=False,
                 verilator_make_gmake=False)
    test.file_cache_clear()
    return int(test.file_grep(test.stats, r'Assertions, NFA link signal nodes cloned\s+(\d+)')[0])


small = cloned_nodes(SIZE_SMALL)
large = cloned_nodes(SIZE_LARGE)
if not small:
    test.error("No link signal nodes cloned, so their growth is not measured")
elif large > MAX_RATIO * small:
    test.error(f"Link signal nodes cloned grew from {small} to {large}, more than linearly")

test.passes()
