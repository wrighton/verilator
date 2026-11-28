#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os
import re

import vltest_bootstrap

test.scenarios('vlt')

# Sanitizer and debug compiler stack frames are larger, so the passes recursing along the
# nest overflow the stack
if (test.have_dev_asan or test.tsan
        or re.search(r'--debug(\s|$)', ' '.join(test.driver_verilator_flags))
        or os.environ.get('VERILATOR_BIN', '').endswith('_dbg')):
    test.skip("Too deep with sanitizers or the debug compiler")

# A $sformatf nested 2048 deep, each level adding 67 characters, must fold
# in bounded memory and produce the whole text
DEPTH = 2048
LEVEL = '$sformatf("<0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef %s>", '

test.top_filename = f"{test.obj_dir}/in.v"

with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("module t;\n  string s;\n  initial begin\n    s = ")
    for _ in range(DEPTH):
        f.write(LEVEL + "\n")
    f.write('"x"' + ")" * DEPTH + ";\n")
    f.write(f"    if (s.len() != {DEPTH * 67 + 1}) $stop;\n")
    f.write('    $write("*-* All Finished *-*\\n");\n    $finish;\n  end\nendmodule\n')

test.compile(verilator_flags2=["--stats"])

memUsageMB = int(test.file_grep(test.stats, r'Peak Memory Usage \(MB\) +(\d+)')[0])

if memUsageMB > 64:
    test.error("Consumed over 64MB memory")

test.execute()

test.passes()
