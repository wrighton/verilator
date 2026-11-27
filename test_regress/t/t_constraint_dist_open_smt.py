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

if not test.have_solver:
    test.skip("No constraint solver installed")

# Exercise the solver sampler, not the native one-variable DIST draw.
test.compile(verilator_flags2=['-fno-constraint-fast'])

test.execute()

# Point trials may fail only in the intentionally clipped state-index section.
sim_log = test.obj_dir + '/vlt_sim.log'
test.file_grep_not(sim_log, r'DIST weighting limited: sampling limit reached')
contents = test.file_contents(sim_log)
before, begin, rest = contents.partition('Begin clipped state-index DIST\n')
clipped, end, after = rest.partition('End clipped state-index DIST\n')
if not begin or not end:
    test.error('Missing clipped state-index DIST markers')
if 'DIST weighting limited:' in before or 'DIST weighting limited:' in after:
    test.error('Unexpected point warning outside the clipped state-index DIST')
for line in clipped.splitlines():
    if ('DIST weighting limited:' in line
            and not line.endswith('DIST weighting limited: no uniform point found in the selected bucket')):
        test.error('Unexpected sampling diagnostic in the clipped state-index DIST')

test.passes()
