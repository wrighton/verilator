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

test.lint(verilator_flags2=['--debug-emitv', '--dumpi-tree 3'])

output_v = test.glob_one(test.obj_dir + '/' + test.vm_prefix + '_*_width.tree.v')
test.file_grep(output_v, r'assign middle = pair\[5:2\];')
test.file_grep(output_v, r'assign one = pair\[3\];')

test.passes()
