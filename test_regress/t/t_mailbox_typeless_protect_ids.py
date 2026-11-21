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
test.top_filename = "t/t_mailbox_typeless.v"

# This test makes randomly named .cpp/.h files, which tend to collect, so remove them first
for filename in (glob.glob(test.obj_dir + "/*_PS*.cpp") + glob.glob(test.obj_dir + "/*_PS*.h") +
                 glob.glob(test.obj_dir + "/*.d")):
    test.unlink_ok(filename)

# --no-timing, as --protect-ids does not support std::process
test.compile(verilator_flags2=["--binary --no-timing --protect-ids --protect-key SECRET_KEY"])

test.execute()

for filename in glob.glob(test.obj_dir + "/*.cpp"):
    test.file_grep_not(filename, r'color_t|Derived')

test.passes()
