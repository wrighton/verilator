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

test.compile(verilator_flags2=['--assert', '--stats'], verilator_make_gmake=False)

test.file_grep(test.stats, r'Assertions, NFA per-attempt properties\s+(\d+)', 4)
test.file_grep(test.stats, r'Assertions, NFA per-attempt antecedent length branches\s+(\d+)', 13)
test.file_grep(test.stats, r'Assertions, NFA per-attempt antecedent branch ticks\s+(\d+)', 356)
test.file_grep(test.stats, r'Assertions, NFA per-attempt antecedents beyond limits\s+(\d+)', 6)

test.passes()
