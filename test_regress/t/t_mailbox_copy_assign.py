#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

# A shallow copy of a mailbox, a built-in class, having its own waiters is a rule of Verilator
test.scenarios('vlt_all')
test.top_filename = "t/t_mailbox_copy.v"

test.compile(verilator_flags2=["--binary", "+define+T_ASSIGN_EVENTS"])

test.execute()

# Events are assignable in this model
if test.vlt_all:
    test.file_grep_any(test.glob_some(test.obj_dir + "/*.h"), r'VlAssignableEvent')

test.passes()
