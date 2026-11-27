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

# Also run the debug build
test.compile(verilator_flags2=[
    '--binary', '--x-assign unique', '--x-initial unique', '--debug', '--debugi 0', '--stats'
])

# One copy of c_n for each other set of defaults: 12, 109, 55 and 77
test.file_grep(test.stats, r'Assertions, checker copies for formal defaults\s+(\d+)', 4)

# Unknown bits take random values, so run with several seeds
for seed in (1, 2, 3, 4, 5, 6, 7, 8):
    test.execute(all_run_flags=['+verilator+seed+' + str(seed), '+verilator+rand+reset+2'])

test.passes()
