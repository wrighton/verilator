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


def wider(line, bits, target=32):
    return (r'%Warning: \S+:' + str(line) + r': Stream of ' + str(bits) +
            r' bits is wider than its fixed-size target of ' + str(target) +
            r' bits \(IEEE 1800-2023 11\.4\.14\)\.')


# Once per width in a row, again after it fits, per assignment and instance
for line in (32, 33):
    test.file_grep_count(test.run_log_filename, wider(line, 40), 6)
    test.file_grep_count(test.run_log_filename, wider(line, 48), 2)
test.file_grep_count(test.run_log_filename, wider(61, 40), 1)
test.file_grep_count(test.run_log_filename, wider(62, 40), 1)
for target in (16, 24):
    test.file_grep_count(test.run_log_filename, wider(67, 32, target), 1)
    test.file_grep_count(test.run_log_filename, wider(67, 40, target), 1)
test.file_grep_count(
    test.run_log_filename, r'%Warning: \S+:63: Stream target of 8-bit elements requires a whole'
    r' number of elements, but the source provides 12 bits', 1)

test.passes()
