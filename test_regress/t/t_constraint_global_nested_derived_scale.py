#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.scenarios('vlt')

N_SMALL = 50
N_LARGE = N_SMALL * 4


def scanned_classes(n):
    # Many rand handles of classes with derived classes declaring constraints and callbacks:
    # finding the callbacks of each handle's class hierarchy scans each class once
    test.top_filename = f"{test.obj_dir}/t_{n}.v"
    with open(test.top_filename, "w", encoding="utf8") as f:
        for i in range(n):
            f.write(f"class Item{i};\n")
            f.write("  rand bit [7:0] v;\n")
            f.write("endclass\n")
            f.write(f"class ItemSub{i} extends Item{i};\n")
            f.write(f"  constraint c_v {{v > 8'd{i % 200};}}\n")
            f.write("  function void pre_randomize();\n")
            f.write("  endfunction\n")
            f.write("endclass\n")
            f.write(f"class Holder{i};\n")
            f.write(f"  rand Item{i} h;\n")
            f.write("  rand bit [7:0] k;\n")
            f.write("  constraint c_k {k == h.v;}\n")
            f.write("endclass\n")
        f.write("module t;\n")
        f.write("  initial begin\n")
        for i in range(n):
            f.write(
                f"    begin automatic Holder{i} holder = new; void'(holder.randomize()); end\n")
        f.write("  end\n")
        f.write("endmodule\n")
    test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)
    # Read anew, as test.file_contents() keeps the contents of the first compile
    with open(test.stats, 'r', encoding="utf8") as fh:
        stats = fh.read()
    scanned = re.search(r'Randomize, Classes scanned for pre/post_randomize wrappers\s+(\d+)',
                        stats)
    if not scanned:
        test.error("Classes scanned not found in " + test.stats)
    return int(scanned.group(1))


small = scanned_classes(N_SMALL)
large = scanned_classes(N_LARGE)
if small == 0 or large != small * N_LARGE // N_SMALL:
    test.error("Finding pre/post_randomize wrappers scaled superlinearly with merged classes: " +
               f"{N_SMALL} scanned {small} classes, {N_LARGE} scanned {large}")

test.passes()
