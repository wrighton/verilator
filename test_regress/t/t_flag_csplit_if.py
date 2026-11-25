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

LIMIT = 1000

test.compile(verilator_flags2=['--binary', '--stats', '--output-split-cfuncs', str(LIMIT)])

test.execute()

# No function is far over the limit, also when all logic of a process is under one 'if'
largest = int(test.file_grep(test.stats, r'Size of largest function, nodes, emitc\s+(\d+)')[0])
if largest > 5 * LIMIT:
    test.error("Largest function has " + str(largest) + " nodes, limit " + str(LIMIT))

# The temporary of the process stays local to its function
test.file_grep(test.stats, r'Optimizations, Vars localized\s+(\d+)', 4)

test.passes()
