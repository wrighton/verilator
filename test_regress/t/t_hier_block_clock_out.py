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

test.compile(verilator_flags2=['--binary', '--hierarchical', '--vpi', '--stats'])

# The update of the block producing the clock runs in the NBA region, not the active region
test.file_grep(test.obj_dir + '/V' + test.name + '__hier.dir/V' + test.name + '__stats.txt',
               r'Scheduling, size of region: Active\s+(\d+)', 54)

test.execute()

test.passes()
