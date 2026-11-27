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

test.compile(verilator_flags2=['--binary', '--coverage-user'])

test.execute(check_finished=True,
             all_run_flags=["+verilator+coverage+file+" + test.coverage_filename])

# Each collected cover counts its passes
test.file_grep(test.coverage_filename, r"\x01h\x02t\.cover_static' [1-9]")
test.file_grep(test.coverage_filename, r"\x01h\x02t\.cover_until' [1-9]")

test.passes()
