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
test.top_filename = "t/t_interface_virtual_nba_mon.v"

test.compile(verilator_flags2=['--stats'], threads=4)

# The barrier of the monitor reads is not in any MTask, and is rerouted only within MTasks.
# Lower bounds, as the partitioning decides what is in an MTask (512 edges are saved here).
rerouted = int(test.file_grep(test.stats, r'MTask graph, variables rerouted per MTask\s+(\d+)')[0])
saved = int(
    test.file_grep(test.stats,
                   r'MTask graph, edges saved rerouting variables per MTask\s+(\d+)')[0])
if rerouted < 1 or saved < 256:
    test.error("Barrier not rerouted within MTasks: {} rerouted, {} edges saved".format(
        rerouted, saved))

test.execute()

test.passes()
