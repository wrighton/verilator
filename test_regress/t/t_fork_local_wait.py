#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(verilator_flags2=["--binary"])

test.execute()

# The single process waiting through a loop index, and the finish, keep static triggers
test.file_grep_count(test.obj_dir + "/" + test.vm_prefix + "___024root.h",
                     r'VlTriggerScheduler __VtrigSched', 2)

test.passes()
