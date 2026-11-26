#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vltmt')

# Thread-safe DPI, and the threads evaluating in parallel whatever may be
test.compile(make_main=False,
             verilator_flags2=[
                 '--exe', test.pli_filename, '--no-timing', '--stats', '--threads-dpi', 'all',
                 '-fno-inline', '-CFLAGS', '-DVL_THREADS_SERIAL_COST=0'
             ],
             threads=4)

test.file_grep(test.stats, r'Optimizations, DPI import wrappers reusing results\s+(\d+)', 1)
# The callers, with no ordering between them otherwise, run serially
test.file_grep(test.stats, r'Scheduling, MTasks with DPI hazards\s+(\d+)', 4)
test.file_grep(test.stats, r'Scheduling, MTasks with DPI hazards reusing results\s+(\d+)', 4)

test.execute()

test.passes()
