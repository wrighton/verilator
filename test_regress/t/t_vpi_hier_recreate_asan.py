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
test.top_filename = "t/t_vpi_hier_exit_asan.v"
test.pli_filename = "t/t_vpi_hier_exit_asan.cpp"

if test.tsan:
    test.skip("ThreadSanitizer not compatible with AddressSanitizer\n")

test.compile(make_main=False,
             make_top_shell=False,
             verilator_flags2=[
                 "--exe --vpi --hierarchical", test.pli_filename,
                 "-CFLAGS -fsanitize=address -LDFLAGS -fsanitize=address", "-CFLAGS -DT_RECREATE"
             ])

test.execute()

test.passes()
