#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import glob

import vltest_bootstrap

test.scenarios('vlt')
test.top_filename = "t/t_defparam_gen_block.v"

test.compile(verilator_flags2=["--binary", "-Wno-DEFPARAM", "--dump-tree", "--dump-tree-json"])

# The defparams that V3Param gives the value of by their path from the module
linkdot = sorted(glob.glob(test.obj_dir + "/*_linkdotparam.tree"))[0]
test.file_grep(linkdot, r'DEFPARAM .* \[FROMMOD\]')
test.file_grep(linkdot + ".json", r'"fromModule":true')

test.execute()

test.passes()
