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

test.compile(verilator_flags2=['--stats', '-Wno-UNOPTTHREADS'])

test.execute()

test.file_grep(test.stats, r'NBA, variables using FlagShared scheme\s+(\d+)', 1)
test.file_grep(test.stats, r'NBA, variables using FlagArray scheme\s+(\d+)', 13)

# The number of NBA flag and value variables does not scale with the array sizes, with a
# variable per NBA there would be over 2000 for 'big' alone
nDecls = 0
for filename in (test.glob_some(test.obj_dir + "/" + test.vm_prefix + "*.h") +
                 test.glob_some(test.obj_dir + "/" + test.vm_prefix + "*.cpp")):
    with open(filename, 'r', encoding="utf8") as fh:
        nDecls += len(re.findall(r'\b__Vdly_(?:Set|Val)__\w+;', fh.read()))
if nDecls > 100:
    test.error("Too many NBA flag and value variables: " + str(nDecls))

test.passes()
