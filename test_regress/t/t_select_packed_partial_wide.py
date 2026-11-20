#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os

import vltest_bootstrap

test.scenarios('vlt')

# Only elaboration is run, as later lint passes do not support variables this wide. The
# harness passes a test outright once Verilator prints its --debug-exit message, without
# reporting any later check, so the message is redirected to a file and checked there.
log = test.obj_dir + "/elab.log"
test.run(cmd=[
    os.environ["VERILATOR_ROOT"] + "/bin/verilator", "--lint-only", "--debug-exit-elab",
    "--dump-tree", "-Mdir", test.obj_dir, test.top_filename, ">", log, "2>&1"
],
         verilator_run=True)
test.file_grep(log, r'--debug-exit-elab: Exiting after elaboration pass')

tree = test.glob_one(test.obj_dir + '/*_width.tree')
# Each padded select is the result width, of an in-range select and a compact pad
test.file_grep_count(tree, r'CONCAT .*@\(G/w4194302\)', 2)
test.file_grep_count(tree, r'REPLICATE .*@\(G/w2097151\)', 2)
test.file_grep_not(tree, r'@\(G/w-')

test.passes()
