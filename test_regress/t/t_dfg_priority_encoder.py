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

test.compile(verilator_flags2=["--stats"])

# The exponential C++ compile time only shows with optimized C++, so check the peephole instead
test.file_grep(test.stats, r'Optimizations, DFG, Peephole, replace or with and of not\s+(\d+)', 308)

test.execute()

test.passes()
