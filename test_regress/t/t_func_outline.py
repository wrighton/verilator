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

test.compile(verilator_flags2=["--binary --output-split-cfuncs 100 --stats"])

# VL_KEEP_THIS stays in the coroutine, not in a function made from it
files = test.glob_some(test.obj_dir + "/" + test.vm_prefix + "*.cpp")
test.file_grep_any(files, r'::__VnoInFunc_run\([^{]*\{[^}]*VL_KEEP_THIS;')

# The new functions of the DPI export take its process
files = test.glob_some(test.obj_dir + "/" + test.vm_prefix + "_t__*.cpp")
test.file_grep_any(files, r'__Vdpiexp_dexp\w*__outline\d+\(VlProcessRef vlProcess')

test.execute()

test.file_grep(test.stats, r'Outline, functions created\s+(\d+)', 72)

test.passes()
