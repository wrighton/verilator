#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

# The wait queues of a mailbox are emitted as declared in the std package
test.scenarios('vlt')
test.top_filename = "t/t_mailbox.v"

test.lint(
    v_flags=["--lint-only", "--timing", "--dumpi-tree 9", "--dumpi-V3EmitV 9", "--debug-emitv"])

output_v = test.glob_one(test.obj_dir + "/" + test.vm_prefix + "_*_widthcommit.tree.v")
test.file_grep(output_v, r'local chandle m_getQueue;')
test.file_grep(output_v, r'local chandle m_putQueue;')

test.passes()
