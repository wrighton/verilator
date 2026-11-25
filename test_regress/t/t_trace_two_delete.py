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
test.top_filename = "t/t_trace_two_a.v"

if test.tsan:
    test.skip("ThreadSanitizer not compatible with AddressSanitizer\n")

flags = [
    "--cc", "--trace-vcd", "+define+TRACE_FMT=vcd", "+define+TEST_DUMP",
    "-CFLAGS -fsanitize=address -LDFLAGS -fsanitize=address"
]

# Verilate 'b'
test.compile(make_main=False,
             verilator_make_gmake=False,
             top_filename='t_trace_two_b.v',
             vm_prefix='Vt_trace_two_b',
             verilator_flags2=flags)

# Create the ALL.cpp for 'b'
test.run(logfile=test.obj_dir + "/make_first_ALL.log",
         cmd=[
             os.environ["MAKE"], "-C", "" + test.obj_dir, "-f", "Vt_trace_two_b.mk",
             "Vt_trace_two_b__ALL.cpp"
         ])

# Build 'a', this includes ALL.cpp for 'b'
test.compile(make_main=False, verilator_flags2=flags + ['--exe', test.pli_filename])

test.execute()

# The values of 'b' stop changing once it is deleted
test.vcd_identical(test.trace_filename, test.golden_filename)

test.passes()
