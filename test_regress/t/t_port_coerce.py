#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(timing_loop=True, verilator_flags2=['--timing'])

# A top-level port is not coerced
test.file_grep(test.obj_dir + "/" + test.vm_prefix + ".h", r'VL_IN8\(&tin,')

test.execute()

test.passes()
