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

# -fno-dfg keeps the intermediate signal of the second case for V3Gate
test.sim_time = 5000

test.compile(verilator_flags2=['--stats', '-fno-dfg'])

test.execute()

test.file_grep(test.stats, r'Optimizations, Gate signals not inlined due to cost\s+(\d+)', 2)
test.file_grep(test.stats, r'Optimizations, Gate signals inlined\s+(\d+)', 2)

test.passes()
