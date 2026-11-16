#!/usr/bin/env python3
# DESCRIPTION: Verilator assertion-control regression
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
import vltest_bootstrap

test.scenarios('vlt')
test.compile(make_top_shell=False, make_main=False, threads=1,
             verilator_flags2=['--savable', '--no-timing', '--assert',
                               '--exe', test.pli_filename],
             make_flags=['-j2'])
test.execute()
test.passes()
