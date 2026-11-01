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

test.scenarios('vlt_all')

test.compile()

# Reg's callbacks are also called from Block, so Reg's randomize() calls them instead of a copy
calls = set()
for filename in test.glob_some(test.obj_dir + "/*.cpp"):
    with open(filename, 'r', encoding="utf8") as fh:
        for funcText in fh.read().split("\n}\n"):
            if "Reg::__VnoInFunc_randomize(" in funcText:
                calls.update(re.findall(r'->__VnoInFunc___VrandCb_(pre|post)\(', funcText))
if calls != {"pre", "post"}:
    test.error("Reg::randomize does not call its nested callbacks, calls: " + str(calls))

test.execute()

test.passes()
