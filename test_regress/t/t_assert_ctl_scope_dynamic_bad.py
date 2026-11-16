#!/usr/bin/env python3
# DESCRIPTION: Verilator assertion-control regression
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
import vltest_bootstrap

test.scenarios('vlt_all')
test.compile(make_top_shell=False, verilator_flags2=['--assert', '--no-timing'],
             threads=2 if test.vltmt else 1, make_flags=['-j2'])
test.execute()
if test.file_contents(test.run_log_filename).count("Bad $assertcontrol control_type '12'") != 4:
    test.error('Dynamic assertion control must diagnose once per call')
test.passes()
