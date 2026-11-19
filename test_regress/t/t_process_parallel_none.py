#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vltmt')

test.compile(verilator_flags2=["--binary", "--stats", "--no-threads-coarsen"], threads=2)

test.execute()

# No block controls processes, so none runs alone
test.file_grep_not(test.stats, r'Scheduling, MTasks with process control')

test.passes()
