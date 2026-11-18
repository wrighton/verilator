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

test.compile(verilator_flags2=['--binary'])

# A module's level is the indentation of the debug messages of its functions
levels = {}
for filename in test.glob_some(test.obj_dir + "/" + test.vm_prefix + "_*.cpp"):
    for match in re.finditer(r'VL_DBG_MSGF\("\+( *)\w+__03A__03A(mon|drv)__W(\d+)::',
                             test.file_contents(filename)):
        levels[match.group(2) + match.group(3)] = len(match.group(1))

# Mirrored classes have identical levels
rooted = ('mon2', 'drv3', 'mon5', 'drv6', 'mon7', 'drv9')
peers = ('drv2', 'mon3', 'drv5', 'mon6', 'drv7', 'mon9')
for mirrored in (rooted, peers):
    if len({levels[name] for name in mirrored}) != 1:
        test.error("Levels of " + str(mirrored) + " differ: " + str(levels))

test.execute()

test.passes()
