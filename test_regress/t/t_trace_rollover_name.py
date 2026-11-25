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
test.top_filename = "t_trace_cat.v"

test.compile(make_top_shell=False,
             make_main=False,
             v_flags2=["--trace-vcd --exe", test.pli_filename])

test.execute()

# Same trace as t_trace_rollover
os.system("cat " + test.obj_dir + "/simnodot_cat0000 " + test.obj_dir + "/simnodot_cat0001 > " +
          test.obj_dir + "/simnodot.vcd")
test.vcd_identical(test.obj_dir + "/simnodot.vcd", "t/t_trace_rollover.out")

test.file_grep_not(test.obj_dir + "/dir.x/sim_cat0000", r'^#')
test.file_grep(test.obj_dir + "/dir.x/sim_cat0001", r'^#')

test.file_grep_not(test.obj_dir + "/simwrap_cat9999.vcd", r'^#')
test.file_grep(test.obj_dir + "/simwrap_cat10000.vcd", r'^#')
test.file_grep(test.obj_dir + "/simwrap_cat10001.vcd", r'^#')
if os.path.exists(test.obj_dir + "/simwrap_cat0000.vcd"):
    test.error("Rollover reused a file name")

test.passes()
