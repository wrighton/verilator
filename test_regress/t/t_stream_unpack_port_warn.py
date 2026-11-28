#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2024 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(verilator_flags2=['--binary'])

test.execute()

test.file_grep(
    test.run_log_filename, r'%Warning: \S+:18: Stream of 24 bits is wider than its fixed-size'
    r' target of 16 bits \(IEEE 1800-2023 11\.4\.14\)\.')

test.passes()
