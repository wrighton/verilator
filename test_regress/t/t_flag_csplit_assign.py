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

LIMIT = 500

test.compile(verilator_flags2=['--binary', '--stats', '--output-split-cfuncs', str(LIMIT)])

test.execute()

test.file_grep(test.stats, r'Outline, wide assignments split\s+(\d+)', 2)
# The boundaries of parts of the costly assignment avoid its divisions
test.file_grep(test.stats, r'Outline, wide assignment part boundaries moved\s+([1-9]\d*)')

# The functions are within a small multiple of the limit
largest = int(test.file_grep(test.stats, r'Size of largest function, nodes, emitc\s+(\d+)')[0])
if largest > 4 * LIMIT:
    test.error(f"Largest function has {largest} nodes, limit is {LIMIT}")

test.passes()
