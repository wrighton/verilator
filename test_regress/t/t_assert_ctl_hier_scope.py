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

test.compile(
    verilator_flags2=['--binary', '--assert', '--hierarchical', '--dump-tree', '--dump-tree-json'])

test.execute()

# A scoped control above a block, so also the blocks below that, selects its assertions
for block in ['Vleaf', 'Vinner', 'Vempty']:
    test.file_grep(test.obj_dir + "/" + block + "__hierMkArgs.f", r'--hierarchical-assert-control')

test.passes()
