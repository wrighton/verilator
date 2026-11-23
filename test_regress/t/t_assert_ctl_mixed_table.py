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
test.compile(verilator_flags2=['--binary', '--assert', '--stats'], threads=2 if test.vltmt else 1)
test.execute()
# Four bank sites, four first-call overlays, eight top sites, and four alias overlays.
test.file_grep(test.stats, r'Assertions, Scoped table entries\s+(\d+)', 20)
test.file_grep(test.stats, r'Assertions, Shared absolute target lists\s+(\d+)', 2)
test.passes()
