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

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

test.execute()

if test.vlt_all:
    # The randomizer gets the names of the fields wider than 64 bits as strings
    cpp_files = test.glob_some(test.obj_dir + "/*.cpp")
    for regexp in [
            r'clear_var\("item\.w"s\)', r'clear_var\("item\.p"s\)',
            r'clear_var\("holder\.arr\.1\.w"s\)', r'set_var_disabled\("item\.w"s\)',
            r'set_var_disabled\("holder\.arr\.1\.w"s\)'
    ]:
        test.file_grep_any(cpp_files, regexp)

test.passes()
