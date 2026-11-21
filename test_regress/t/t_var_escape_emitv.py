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

# Escaped identifiers stay escaped within the hierarchical names of scoped debug Verilog
test.compile(verilator_flags2=["--debug-emitv", "--dumpi-tree 3"],
             verilator_make_gmake=False,
             make_main=False)

scoped = test.glob_one(test.obj_dir + "/" + test.vm_prefix + "_*_scope.tree.v")
test.file_grep(scoped, r'logic \\g/b \[1\]\.\\v/x ;')
test.file_grep(scoped, r't\.\\a/b  <= \(\\g/b \[1\]\.\\v/x  \^ \\u/s \.\\s/v \);')

test.passes()
