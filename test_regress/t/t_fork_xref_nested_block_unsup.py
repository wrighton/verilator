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

test.compile(verilator_flags2=['--binary', '--timing'], fails=True)

# Both references, 16:17 and 35:26, as for a reference from outside the fork
test.file_grep(test.compile_log_filename,
               r"%Error: t/t_fork_xref_nested_block_unsup.v:16:17: Can't find varpin scope")
test.file_grep(test.compile_log_filename,
               r"%Error: t/t_fork_xref_nested_block_unsup.v:35:26: Can't find varpin scope")
test.file_grep_not(test.compile_log_filename, r"Internal Error")

test.passes()
