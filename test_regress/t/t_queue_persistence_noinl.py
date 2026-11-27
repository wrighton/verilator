#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2024 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')
test.top_filename = "t/t_queue_persistence.v"

if not test.have_coroutines:
    test.skip("No coroutine support")

test.compile(verilator_flags2=["--binary --fno-inline +define+TEST_NOINLINE", "--dump-tree"])

# Elements passed by reference are pins
task_tree = test.glob_one(test.obj_dir + "/V*_task.tree")
test.file_grep(task_tree, r"DYNARRAYSEL.*\[REFPIN\]")
test.file_grep(task_tree, r"QUEUESEL.*\[REFPIN\]")

test.execute()

test.passes()
