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
test.top_filename = "t/t_hier_block_param_stub.v"

test.compile(verilator_flags2=[
    '--stats', '--timing', '--hierarchical', '-y', test.t_dir +
    '/t_hier_block_param_stub_dir', '-fno-hier-param-stub'
])

test.execute()

# The top's run links the instances inside the block too
top_stats = test.obj_dir + "/" + test.vm_prefix + "__hier.dir/" + test.vm_prefix + "__stats.txt"
test.file_grep(top_stats, r'LinkCells, Hierarchical blocks stubbed\s+(\d+)', 0)
test.file_grep(top_stats, r'LinkDot, Instances\s+(\d+)', 37)

test.passes()
