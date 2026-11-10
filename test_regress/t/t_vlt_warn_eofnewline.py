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
test.top_filename = test.obj_dir + "/t.v"

LATCH = "  always_latch if (c) q <= d;  // COMBDLY\n"

# Module name -> file contents; all but the last have no newline at end of file
SOURCES = {
    "cmt":
    "module cmt (input c, input d, output logic q);\n" + LATCH + "endmodule\n// Comment",
    "blk":
    "module blk (input c, input d, output logic q);\n" + LATCH + "endmodule\n/* Comment */",
    "code":
    "module code (input c, input d, output logic q);\n" + LATCH + "endmodule",
    "one":
    "module one (input c, input d, output logic q); always_latch if (c) q <= d; endmodule",
    "pragma":
    "/*verilator_bad*/ module pragma (input c, input d, output logic q);\n" + LATCH +
    "endmodule\n",
}


def gen():
    files = []
    for name, contents in SOURCES.items():
        filename = test.obj_dir + "/" + name + ".v"
        with open(filename, 'w', encoding="utf8") as fh:
            fh.write(contents)
        files.append(filename)
    with open(test.top_filename, 'w', encoding="utf8") as fh:
        fh.write("module t (input c, input d);\n")
        for name in SOURCES:
            fh.write("  " + name + " u_" + name + " (.c, .d, .q());\n")
        fh.write("endmodule\n")
    return files


test.lint(verilator_flags2=[test.vlt_filename] + gen())

test.passes()
