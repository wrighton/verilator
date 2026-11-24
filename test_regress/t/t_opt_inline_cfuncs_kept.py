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

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

# Reg's pre- and post-randomize phases are also called from Block, whose constraint selects
# through Reg's fields, so the parts of Reg's randomize() call them instead of a copy
calls = set()
for filename in test.glob_some(test.obj_dir + "/*.cpp"):
    with open(filename, 'r', encoding="utf8") as fh:
        for funcText in fh.read().split("\n}\n"):
            if ("Reg::__VnoInFunc_randomize(" in funcText
                    or "Reg::__VnoInFunc___VrandNoPre(" in funcText):
                calls.update(re.findall(r'->__VnoInFunc___Vrand(Pre|Post)\(', funcText))
if calls != {"Pre", "Post"}:
    test.error("Reg::randomize does not call its pre- and post-randomize phases, calls: " +
               str(calls))

test.execute()

test.passes()
