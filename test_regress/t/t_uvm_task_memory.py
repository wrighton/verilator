#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.priority(50)
test.scenarios('vlt')
test.top_filename = 't/t_uvm_hello.v'

if test.have_dev_gcov:
    test.skip("Test suite intended for full dev coverage without needing this test")
if test.have_dev_asan:
    test.skip("ASAN inflates memory usage by retaining freed stuff")

# Growth of peak memory in V3Task, relative to the peak before it. V3Task kept every
# converted class method until it finished, raising the peak by about 8% here; now under 1%.
MAX_GROWTH = 0.03

test.compile(
    v_flags2=["--timing", "--stats", "+incdir+t/uvm", "t/uvm/uvm_pkg_all_v2020_3_1_nodpi.svh"],
    make_main=False,
    verilator_make_gmake=False)

with open(test.stats, 'r', encoding="utf8") as fh:
    peaks = re.findall(r'Stage, Memory peak \(MB\), \d+_(\S+)\s+(\S+)', fh.read())
stages = [name for name, _ in peaks]
if 'task' not in stages:
    test.error("Task stage memory not found in " + test.stats)
index = stages.index('task')
before = float(peaks[index - 1][1])
growth = (float(peaks[index][1]) - before) / before
if growth > MAX_GROWTH:
    test.error(f"V3Task raised peak memory by {growth:.1%} (over {MAX_GROWTH:.0%})")

test.passes()
