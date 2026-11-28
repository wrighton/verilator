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

# Verilating, in time not exponential in the depth of the type; a variable of this type is too
# large to simulate, as each queue holds a default element
test.timeout(30 if not test.have_dev_asan else 60)

test.compile(verilator_make_gmake=False)

test.passes()
