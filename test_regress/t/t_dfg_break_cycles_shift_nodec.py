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

test.top_filename = "t/t_dfg_break_cycles_shift.v"

# Without decomposition the array element is traced as such
test.compile(verilator_flags2=['--binary', '--stats', '-fno-decompose', '-fdfg-synthesize-all'])

test.execute()

test.file_grep(test.stats, r'Optimizations, DFG, BreakCycles, made acyclic\s+(\d+)', 6)
test.file_grep(test.stats, r'Optimizations, DFG, BreakCycles, ranges traced in chunks\s+(\d+)', 3)
# Tracing each chain whole made the code quadratic in the width (nba code size 381000)
nbaSize = int(test.file_grep(test.stats, r"Size of eval, instr - 'nba', emitc\s+(\d+)")[0])
if nbaSize > 340000:
    test.error("Evaluation code too large: " + str(nbaSize))

test.passes()
