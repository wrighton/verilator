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
test.top_filename = "t/t_savable.v"

# Trivially constructible members of 'sub' in named structs
test.compile(v_flags2=["--savable", "--comp-limit-members", "2"], save_time=500)

test.file_grep(test.obj_dir + "/" + test.vm_prefix + "_sub__Slow.cpp",
               r'os<<__Vg\d+\.__Vg\d+\.__Vg\d+\.__PVT__cyc;')

test.execute(check_finished=False, all_run_flags=['+save_time=500'])

if not os.path.exists(test.obj_dir + "/saved.vltsv"):
    test.error("Saved.vltsv not created")

test.execute(all_run_flags=['+save_restore=1'])

test.passes()
