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

test.compile(verilator_flags2=['--binary', '--x-initial', 'unique', '--stats'])

if test.vlt_all:
    # Other source partitions: asymmetric 3, inverse 1, sole/pair modules 2+2,
    # packed module 2. Generated drivers keep 128+256 distinct inlined contexts.
    # Flat specializations each have one context and one occupied STRONG rank.
    test.file_grep(test.stats, r'Tristate, External interface rank pairs\s+(\d+)',
                   10 + 128 + 256 + 2)
    test.execute(all_run_flags=['+verilator+rand+reset+2'])
else:
    test.execute()

test.passes()
