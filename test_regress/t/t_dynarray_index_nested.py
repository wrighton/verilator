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

test.compile()

# Each nested select is emitted once, not again for each enclosing index check
selects = sum(test.file_contents(f).count('.at(') for f in test.glob_some(test.obj_dir + '/*.cpp'))
if selects > 100:
    test.error('Nested selects emitted ' + str(selects) + ' times')

test.execute()

test.passes()
