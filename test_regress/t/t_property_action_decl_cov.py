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
test.top_filename = "t/t_property_action_decl.v"

test.compile(verilator_flags2=['--binary', '--coverage-user', '+define+T_COVER_COLLECTED'])

test.execute(check_finished=True,
             all_run_flags=["+verilator+coverage+file+" + test.obj_dir + "/coverage.dat"])

# Both collected covers count their passes
test.file_grep_count(test.obj_dir + "/coverage.dat", r"v_user/t.*' [1-9]", 2)

test.passes()
