#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(verilator_flags2=['--binary'])

test.execute()

# A continuous assignment warns whenever its logic is evaluated, so the count is not checked
wider = r'Stream of 40 bits is wider than its fixed-size target of 32 bits \(IEEE 1800-2023 11\.4\.14\)\.'
test.file_grep(test.run_log_filename, r'%Warning: \S+:30: ' + wider)
test.file_grep(test.run_log_filename, r'%Warning: \S+:31: ' + wider)
test.file_grep(
    test.run_log_filename, r'%Warning: \S+:32: Stream target of 8-bit elements requires a whole'
    r' number of elements, but the source provides 12 bits')

test.passes()
