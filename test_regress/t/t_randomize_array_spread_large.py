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

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + log])

# Each spreading hash samples at most 4096 bits, which of the array's 131072 bits is all.
# The log splits long commands, so their text is joined first.
with open(log, encoding="utf8") as fh:
    commands = ''.join(line[2:].rstrip('\n') for line in fh if line.startswith('  '))
hashes = [part.count('(_ extract') for part in commands.split('(assert (= #b')[1:]]
if not hashes or max(hashes) != 4096:
    test.error("Spreading hashes sample other than at most 4096 bits: " + str(hashes))

test.passes()
