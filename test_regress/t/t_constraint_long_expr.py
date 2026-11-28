#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os
import re

import vltest_bootstrap

test.scenarios('vlt')

# Sanitizer and debug compiler stack frames are larger, so the passes recursing along the
# nest overflow the stack
if (test.have_dev_asan or test.tsan
        or re.search(r'--debug(\s|$)', ' '.join(test.driver_verilator_flags))
        or os.environ.get('VERILATOR_BIN', '').endswith('_dbg')):
    test.skip("Too deep with sanitizers or the debug compiler")

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile(verilator_flags2=["--stats"])

memUsageMB = int(test.file_grep(test.stats, r'Peak Memory Usage \(MB\) +(\d+)')[0])

if memUsageMB > 64:
    test.error("Consumed over 64MB memory")

test.execute()

test.passes()
