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

if test.tsan:
    test.skip("ThreadSanitizer not compatible with AddressSanitizer\n")

# The sanitizers report a shift of the value by its width or more, or a read past its words
test.compile(verilator_flags2=[
    "--binary", "--x-assign fast", "-CFLAGS -fsanitize=address,undefined",
    "-CFLAGS -fno-sanitize-recover=undefined", "-LDFLAGS -fsanitize=address,undefined"
])

test.execute()

test.passes()
