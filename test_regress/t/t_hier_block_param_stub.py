#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(verilator_flags2=[
    '--stats', '--timing', '--hierarchical', '-y', test.t_dir + '/t_hier_block_param_stub_dir'
],
             threads=(2 if test.vltmt else 1))

test.execute()

# The top's run stubs four blocks, so links only its own instances, including those bound by
# blocks, and those in blocks whose parameters use their contents, not those in stubbed blocks
top_stats = test.obj_dir + "/" + test.vm_prefix + "__hier.dir/" + test.vm_prefix + "__stats.txt"
test.file_grep(top_stats, r'LinkCells, Hierarchical blocks stubbed\s+(\d+)', 5)
test.file_grep(top_stats, r'LinkDot, Instances\s+(\d+)', 28)

test.passes()
