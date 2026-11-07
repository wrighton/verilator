#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re

import vltest_bootstrap

test.scenarios('vlt')

test.compile(verilator_flags2=['--timing'], make_main=False, verilator_make_gmake=False)

# The process awaits in w0, w1, ... w7, declared in reverse order. The sensitivities of x, and
# the triggers made from them, follow the creation of the timing domains, not node pointers, as
# these sensitivity expressions do not sort.
code = "".join(test.file_contents(f) for f in test.glob_some(test.obj_dir + "/*.cpp"))
matches = re.findall(r"trigger index \d+ is active: @\(posedge \(p\.sel \? p\.a(\d)", code)
order = [int(n) for n in matches]
if order != list(reversed(range(8))):
    test.error(f"Triggers not in declaration order: {order}")

test.passes()
