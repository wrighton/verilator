#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Michael Wrighton
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')

test.compile(verilator_flags2=['--stats'])

# A real solver cannot run. Successful sampling therefore proves the optimization
# actually bypasses the solver, rather than adding metadata to the old solve path.
test.execute(run_env='VERILATOR_SOLVER=/bin/false')

test.passes()
