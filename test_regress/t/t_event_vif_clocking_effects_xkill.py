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
test.top_filename = "t/t_event_vif_clocking_effects.v"
test.pli_filename = "t/t_event_vif_clocking_effects_pub.cpp"

test.compile(make_main=False,
             verilator_flags2=[
                 "--exe", "--timing", "--stats", "+define+T_XKILL", "-CFLAGS", "-DT_XKILL",
                 "--debugi-V3Timing", "4", test.pli_filename
             ])

test.execute()

test.file_grep(test.stats, r'Timing, event controls on interface events through handles\s+(\d+)',
               0)
test.file_grep(test.stats,
               r'Timing, DPI export tasks that may suspend, keeping all polling\s+(\d+)', 1)
test.file_grep(test.compile_log_filename,
               r"Polled, the design has DPI export tasks that may suspend, wait at")

test.passes()
