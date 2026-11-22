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

test.top_filename = 't/t_assert_ctl_parity.v'
test.compile(verilator_flags2=['--binary', '--assert', '--no-stop-fail', '+define+SEED_CONTROL'],
             threads=2 if test.vltmt else 1)

report = test.obj_dir + '/reports.log'
test.execute(logfile=report)
test.file_grep_count(report, r'Assertion failed in .*check_violation: priority case,', 2)
test.file_grep_count(report, r'Assertion failed in .*check_violation: unique case,', 4)
test.file_grep_count(report, r'Assertion failed in .*check_violation: unique0 case,', 2)

test.passes()
