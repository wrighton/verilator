#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import platform
import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")
if platform.system() != "Linux":
    test.skip("Replacing write() needs Linux")

test.compile(v_flags2=["t/t_randomize_solver_short_write_c.cpp", "-LDFLAGS -ldl"],
             verilator_flags2=['--binary'])

logfile = test.obj_dir + '/sim_short_transfers.log'
test.execute(logfile=logfile)
test.file_grep(logfile, r'Short solver transfers: ([1-9][0-9]*)')

test.passes()
