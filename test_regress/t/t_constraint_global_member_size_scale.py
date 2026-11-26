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

N_SMALL = 500
N_LARGE = N_SMALL * 4


def classify_nodes(n):
    # Many sibling constraints of a rand member selecting element members by a foreach index:
    # classifying their indices visits each node once, whatever constraints precede it
    test.top_filename = f"{test.obj_dir}/t_{n}.v"
    with open(test.top_filename, "w", encoding="utf8") as f:
        f.write("class Entry;\n")
        f.write("  rand bit [15:0] x;\n")
        f.write("endclass\n")
        f.write("class Member;\n")
        f.write("  rand Entry q[$];\n")
        for i in range(n):
            f.write(f"  constraint c_{i} {{foreach (q[j]) q[j].x != 16'd{i};}}\n")
        f.write("endclass\n")
        f.write("class Holder;\n")
        f.write("  rand Member member;\n")
        f.write("  constraint c_size {member.q.size() == 2;}\n")
        f.write("endclass\n")
        f.write("module t;\n")
        f.write("  Holder holder = new;\n")
        f.write("  initial if (holder.randomize() == 0) $stop;\n")
        f.write("endmodule\n")
    test.compile(verilator_flags2=["--stats"], make_main=False, verilator_make_gmake=False)
    # Read anew, as test.file_contents() keeps the contents of the first compile
    with open(test.stats, 'r', encoding="utf8") as fh:
        stats = fh.read()
    nodes = re.search(r'Randomize, Element index nodes visited\s+(\d+)', stats)
    if not nodes:
        test.error("Element index nodes visited not found in " + test.stats)
    return int(nodes.group(1))


small = classify_nodes(N_SMALL)
large = classify_nodes(N_LARGE)
if large != small * N_LARGE // N_SMALL:
    test.error("Classifying element indices scaled superlinearly with sibling constraints: " +
               f"{N_SMALL} constraints visited {small} nodes, {N_LARGE} visited {large}")

test.passes()
