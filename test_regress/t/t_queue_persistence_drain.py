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

test.timeout(30)

test.compile(verilator_flags2=["--binary", "--timing"])

test.execute()

# Keeping each whole queue would allocate about 2 GB
with open(test.run_log_filename, 'r', encoding="utf8") as fh:
    allocated = re.search(r'allocated (\d+) MB', fh.read())
if not allocated or int(allocated.group(1)) > 400:
    test.error("Allocated more memory than expected: " +
               (allocated.group(0) if allocated else "?"))

test.passes()
