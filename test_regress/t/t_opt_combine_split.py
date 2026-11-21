#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(verilator_flags2=['--binary', '--stats', '--output-split-cfuncs', '1'])

test.execute(all_run_flags=['+dis_b'], expect_filename=test.golden_filename)

# Only the functions of the first instance remain
for kind in ('static', 'initial', 'final'):
    insts = set()
    for filename in test.glob_some(test.obj_dir + "/*.cpp"):
        with open(filename, 'r', encoding="utf8") as fh:
            for line in fh:
                match = re.search(r'_eval_' + kind + r'__TOP__t__DOT__(u\d+)\w*\(.*\{$', line)
                if match:
                    insts.add(match.group(1))
    if insts != {'u1'}:
        test.error("_eval_" + kind + " functions of instances " + str(sorted(insts)))

test.file_grep(test.stats, r'Optimizations, Combined CFuncs\s+(\d+)', 37)

test.passes()
