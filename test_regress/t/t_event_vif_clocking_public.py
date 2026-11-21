#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')
# All variables are public, so code outside the model may write the handles, and the waits
# through them evaluate their triggers at every trigger evaluation
test.top_filename = "t/t_event_vif_clocking_rebind.v"

test.compile(verilator_flags2=["--binary", "--stats", "--public-flat-rw"])

test.execute()

# No wait is listed, so the waits awaiting trigger evaluation are not ordered among listed ones

test.file_grep(test.stats, r'Timing, event controls skipping trigger evaluations\s+(\d+)', 28)

test.passes()
