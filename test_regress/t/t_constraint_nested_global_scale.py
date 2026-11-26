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

CONSTRAINTS = 2000

# Many sibling constraints of a member class, all cloned into the class randomizing it
test.top_filename = f"{test.obj_dir}/t_constraint_nested_global_scale.v"
with open(test.top_filename, "w", encoding="utf8") as fh:
    fh.write("class Entry;\n  rand bit [15:0] x;\nendclass\n")
    fh.write("class Member;\n  rand Entry q[$];\n")
    for i in range(CONSTRAINTS):
        fh.write(f"  constraint c_{i} {{foreach (q[j]) q[j].x != 16'd{i};}}\n")
    fh.write("endclass\n")
    # The class randomizing them extends another, which is searched for each name too
    fh.write("class HolderBase;\n  rand bit [7:0] y;\n  constraint c_y {y != 0;}\nendclass\n")
    fh.write("class Holder extends HolderBase;\n  rand Member member;\n")
    fh.write("  constraint c_size {member.q.size() == 2;}\nendclass\n")
    fh.write("module t;\n  Holder holder = new;\n")
    fh.write("  initial if (holder.randomize() == 0) $stop;\nendmodule\n")

test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)

# Linear in the constraints: two steps each, for the class and its base, and one per member of
# the two classes, searched once. Searching the class for each constraint cloned into it was
# quadratic (about CONSTRAINTS / 2 each here)
test.file_grep(test.stats, r'Randomize, Constraint name search steps\s+(\d+)', 2 * CONSTRAINTS + 7)

test.passes()
