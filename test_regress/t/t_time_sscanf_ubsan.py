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
test.top_filename = 't/t_time_sscanf.v'

# Out-of-range real to integer conversions are undefined in C++
test.compile(verilator_flags2=[
    '-CFLAGS -fsanitize=float-cast-overflow -CFLAGS -fno-sanitize-recover=float-cast-overflow',
    '-LDFLAGS -fsanitize=float-cast-overflow'
])

test.execute()

test.passes()
