#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Michael Wrighton
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')
test.top_filename = 't/t_randomize_fast_wide.v'
test.compile(verilator_flags2=['--top-module t_wide', '--protect-ids',
                              '--protect-key SECRET_KEY'])
test.execute(run_env='VERILATOR_SOLVER=/bin/false',
             all_run_flags=['+verilator+wno+unsatconstr+1'])
test.passes()
