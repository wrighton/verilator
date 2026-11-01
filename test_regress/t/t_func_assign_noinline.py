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

test.compile(verilator_flags2=["--binary", "--stats"])

test.execute(all_run_flags=["+names=n1,n3"])

# The 6 in_names calls and the pop_first and fact_twice calls are not inlined
test.file_grep(test.stats,
               r'Optimizations, Function calls in initial assignments not inlined\s+(\d+)', 8)
test.file_grep(test.stats, r'Optimizations, Functions inlined\s+(\d+)', 12)
# So there is one copy of the in_names body, besides the public function and its inlined call
cpp = ""
for filename in test.glob_some(test.obj_dir + "/*.cpp"):
    with open(filename, encoding="utf8") as fh:
        cpp += fh.read()
if cpp.count("VL_VALUEPLUSARGS") != 3:
    test.error("Expected 3 copies of the in_names body, got " + str(cpp.count("VL_VALUEPLUSARGS")))

test.passes()
