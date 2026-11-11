#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(verilator_flags2=['--binary', '--stats'])

test.execute()

# A resumed call enqueues globally; its commit no longer uses cached await domains.
# Both a and sub.y must use that queue, including the NBA before the first await.
test.file_grep(test.stats, r'NBA, variables using GenericGlobal scheme\s+(\d+)', 2)

test.passes()
