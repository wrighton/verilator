#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

# Files with a control file rule are looked up by name about once per file read, not once per token

import re

import vltest_bootstrap

test.scenarios('vlt')
test.top_filename = test.obj_dir + "/t.v"

N_FILES = 50
N_LINES = 400

files = []
for i in range(N_FILES):
    filename = test.obj_dir + "/m" + str(i) + ".v"
    files.append(filename)
    with open(filename, 'w', encoding="utf8") as fh:
        fh.write("module m" + str(i) + " (input [7:0] a, output [7:0] y);\n")
        for j in range(N_LINES):
            fh.write("  wire [7:0] w" + str(j) + " = a + 8'd" + str(j % 200) + ";\n")
        fh.write("  assign y = w" + str(N_LINES - 1) + ";\nendmodule\n")
with open(test.top_filename, 'w', encoding="utf8") as fh:
    fh.write("module t (input [7:0] a, output [7:0] y[" + str(N_FILES) + "]);\n")
    for i in range(N_FILES):
        fh.write("  m" + str(i) + " u" + str(i) + " (.a, .y(y[" + str(i) + "]));\n")
    fh.write("endmodule\n")
vlt = test.obj_dir + "/rules.vlt"
with open(vlt, 'w', encoding="utf8") as fh:
    fh.write('`verilator_config\nlint_off -rule WIDTH -file "*/m1*.v"\n')

test.lint(verilator_flags2=["--stats", vlt] + files)

lookups = int(
    re.search(r'Control, file rule lookups by name\s+(\d+)', test.file_contents(test.stats))[1])
if lookups > 4 * N_FILES:
    test.error("Too many lookups: " + str(lookups))

test.passes()
