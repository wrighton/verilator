#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os

import vltest_bootstrap

test.scenarios('vlt_all')
# The package claims to be in the std package's file, by a 'line directive
std_file = os.path.join(os.environ["VERILATOR_ROOT"], "include", "verilated_std.sv")
with open("t/t_event_vif_clocking_effects.v", encoding="utf8") as fh:
    source = fh.read().replace("__STD_FILE__", std_file)
test.top_filename = test.obj_dir + "/" + test.name + ".v"
test.write_wholefile(test.top_filename, source)

test.compile(verilator_flags2=[
    "--binary", "--stats", "--no-std-package", "+define+T_STDPKG", "--debugi-V3Timing", "4"
])

test.execute()

test.file_grep(test.stats, r'Timing, event controls on interface events through handles\s+(\d+)',
               0)
test.file_grep(test.stats, r'Timing, user C\+\+ code, keeping all polling\s+(\d+)', 1)
test.file_grep(test.compile_log_filename,
               r"Polled, the design has user C\+\+ code at \S+, wait at")

test.passes()
