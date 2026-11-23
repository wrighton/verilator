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

test.compile(verilator_flags2=['--binary', '--assert'], threads=2 if test.vltmt else 1)

report = test.obj_dir + '/assert_reports.log'
test.execute(logfile=report)
test.file_grep_count(report, r'^immediate assertion report: 3$', 1)
test.file_grep_count(report, r'^deferred assertion report: 3$', 1)

test.passes()
