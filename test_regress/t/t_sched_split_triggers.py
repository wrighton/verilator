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

test.compile(verilator_flags2=["--binary", "--x-initial-edge", "--output-split-cfuncs", "10"])

test.execute()

files = test.glob_some(test.obj_dir + "/" + test.vm_prefix + "*.cpp")
# The initialization time triggers were split
test.file_grep_any(files, r'___eval_triggers_initial__act__0\(')
# The virtual interface triggers were split, so are not in the function calling the parts
test.file_grep_any(files, r'___eval_triggers_vec__act\(\w+\* vlSelf\) \{')
test.file_grep_any(files, r'___eval_triggers_vec__ico\(\w+\* vlSelf\) \{')
test.file_grep_any(files, r'__Vtrigprevvif')
for filename in files:
    test.file_grep_not(
        filename,
        r'___eval_triggers_vec__(act|ico)\(\w+\* vlSelf\) \{\n(?:(?!\}\n).*\n)*?.*__Vtrigprevvif')

test.passes()
