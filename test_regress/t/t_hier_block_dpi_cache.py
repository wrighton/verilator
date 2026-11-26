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

test.compile(verilator_flags2=['--binary', '--hierarchical', '--stats'])

# The three instances of the block whose outputs depend on its inputs and clock alone
test.file_grep(test.obj_dir + '/V' + test.name + '__hier.dir/V' + test.name + '__stats.txt',
               r'Optimizations, DPI import wrappers reusing results\s+(\d+)', 3)
test.file_grep(test.obj_dir + '/Vstage_h/stage_h.sv', r'/\*verilator dpi_cache\*/')
test.file_grep_not(test.obj_dir + '/Vimpure_h/impure_h.sv', r'dpi_cache')

test.execute()

test.passes()
