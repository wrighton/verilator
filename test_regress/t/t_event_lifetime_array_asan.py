#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os

import vltest_bootstrap

test.scenarios('vlt_all')
test.top_filename = "t/t_event_lifetime_array.v"

# AddressSanitizer reports any access to an event after its storage is gone
if not test.have_dev_asan:
    test.skip("No AddressSanitizer, needs a build configured with --enable-dev-asan")
if test.tsan:
    test.skip("ThreadSanitizer not compatible with AddressSanitizer\n")

test.setenv("ASAN_OPTIONS",
            os.environ.get("ASAN_OPTIONS", "") + ":detect_stack_use_after_return=1")

test.compile(
    verilator_flags2=["--binary", "-CFLAGS -fsanitize=address -LDFLAGS -fsanitize=address"])

test.execute()

test.passes()
