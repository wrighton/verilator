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

test.compile(verilator_flags2=["--stats"])

test.execute(all_run_flags=["+names=b,c"])

root = test.obj_dir + "/" + test.vm_prefix + "___024root.h"
# String locals of the inlined in_names calls are localized in cold code
test.file_grep_not(root, r'std::string __Vfunc_in_names')
# But not in hot code
test.file_grep(root, r'std::string __Vfunc_hot_fmt__str')
# 9 other variables, and the 3 string locals of each of the 3 in_names calls
test.file_grep(test.stats, r'Optimizations, Vars localized\s+(\d+)', 18)

test.passes()
