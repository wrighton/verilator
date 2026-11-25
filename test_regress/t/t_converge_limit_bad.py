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
test.top_filename = "t/t_converge_bad.v"

test.compile(verilator_flags2=["--binary"])

cases = (("mailbox", "Active"), ("event", "Active"), ("comb", "Settle"), ("nba", "NBA"))
limits = (([], 10000), (["+verilator+converge+limit+1000000"], 1000000))

# Each loop must abort at the default limit and at a large run-time limit
for case, region in cases:
    for flags, limit in limits:
        log = test.obj_dir + "/" + case + "_" + str(limit) + ".log"
        test.execute(fails=True, all_run_flags=["+" + case] + flags, logfile=log)
        test.file_grep(
            log, r"%Error-DIDNOTCONVERGE: " + region +
            r" region did not converge after '--converge-limit' of " + str(limit) + " tries")
        test.file_grep(log, r"raise the limit with .* '\+verilator\+converge\+limit\+<value>'")

# The limit must leave room to count past it
log = test.obj_dir + "/too_large.log"
test.execute(fails=True, all_run_flags=["+verilator+converge+limit+2147483648"], logfile=log)
test.file_grep(
    log, r"'\+verilator\+converge\+limit\+' must be an unsigned integer, greater than 0,"
    r" less than 2147483648")

test.passes()
