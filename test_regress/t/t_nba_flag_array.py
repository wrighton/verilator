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

test.scenarios('vlt_all')

# Shared arrays can serialize model accesses; exercise MT correctness even if there is
# insufficient independent work for two workers. UNOPTTHREADS has no source-local location.
test.compile(threads=2 if test.vltmt else 1,
             verilator_flags2=['--stats', '--x-initial unique', '-Wno-UNOPTTHREADS'])

test.execute()

# Count model-member declarations, not uses or local temporaries. Each bounded size uses
# at most two model members; later passes may localize the arrays, especially with --threads.
members = []
for filename in test.glob_some(test.obj_dir + '/' + test.vm_prefix + '*.h'):
    with open(filename, 'r', encoding='utf8') as fh:
        members += re.findall(
            r'^\s+(?:alignas\([^\n]+?\)\s+)?::[^;\n]+\s+(__Vdly_(?:Set|Val)__\w+);$',
            fh.read(), re.MULTILINE)
if len(members) > 100:
    test.error('Too many NBA flag and value members: ' + str(len(members)))
for instance in ['u_dense16', 'u_dense64', 'u_dense256', 'u_dense16_copy']:
    if len([name for name in members if '__DOT__' + instance + '__DOT__' in name]) > 2:
        test.error('Too many NBA flag/value array members for ' + instance)

test.file_grep(test.stats, r'NBA, variables using FlagArray scheme\s+(\d+)', 16)
test.file_grep(test.stats, r'NBA, variables using FlagShared scheme\s+(\d+)', 6)
test.file_grep(test.stats, r'NBA, variables using GenericGlobal scheme\s+(\d+)', 1)

test.passes()
