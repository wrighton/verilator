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

test.compile(make_main=False,
             verilator_flags2=["--exe --savable --converge-limit 16", test.pli_filename])

test.execute(all_run_flags=["+save"])

# A model restored from a checkpoint is limited by the run-time override
test.execute(all_run_flags=["+verilator+converge+limit+1000"])

log = test.obj_dir + "/default.log"
test.execute(fails=True, logfile=log)
test.file_grep(log, r"Input combinational region did not converge after '--converge-limit' of 16")

test.passes()
