#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(verilator_flags2=["--binary", "--stats"])

test.execute()

# The searches for where the specializations go take a few steps each, and no interface
# reference needs retargeting
test.file_grep(test.stats, r'Param, Clone insertion steps\s+(\d+)', 581)
test.file_grep(test.stats, r'Param, Interface retarget walks\s+(\d+)', 0)

test.passes()
