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
test.top_filename = "t/t_converge_runtime.v"

test.compile(make_main=False,
             verilator_flags2=["--exe --timing --converge-limit 2147483647", test.pli_filename])

test.execute(all_run_flags=["+verilator+converge+limit+50"])

log = test.obj_dir + "/api_max.log"
test.execute(fails=True, all_run_flags=["+api_max"], logfile=log)
test.file_grep(
    log, r"%Error: Convergence limit must be between 1 and 2147483647, or 0 for no override")

test.passes()
