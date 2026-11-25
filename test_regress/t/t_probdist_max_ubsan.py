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
test.timeout(120)

# Signed overflow of a loop counter is undefined in C++
test.compile(verilator_flags2=[
    '-CFLAGS -fsanitize=signed-integer-overflow',
    '-CFLAGS -fno-sanitize-recover=signed-integer-overflow',
    '-LDFLAGS -fsanitize=signed-integer-overflow'
])

test.execute()

test.passes()
