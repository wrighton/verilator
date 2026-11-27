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

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+rand+sampler+default', '+verilator+solver+file+' + log])

# Spreading assumes the bits about 50,000 times in all; dropping one conflicting bit per
# solver check, each naming all the others, assumed them over a million times
assumed = sum(
    line.count('__Va') for line in test.file_contents(log).splitlines()
    if line.lstrip().startswith('(check-sat-assuming'))
if assumed > 200000:
    test.error("Spreading went quadratic: {} assumptions".format(assumed))

test.passes()
