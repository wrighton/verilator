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

test.top_filename = 't/t_constraint_dist_indep.v'

if not test.have_solver:
    test.skip('No constraint solver installed')

test.compile(verilator_flags2=[
    '--binary', '--protect-ids', '--protect-key SECRET_KEY',
    test.top_filename[:-2] + '.cpp'
])

test.execute(all_run_flags=['+verilator+quiet', '+verilator+wno+unsatconstr+1', '+verilator+rand+sampler+default'])

sim_log = test.obj_dir + '/vlt_sim.log'
test.file_grep(sim_log, r'%Warning: .*DIST weighting limited: sampling limit reached$')
test.file_grep_not(sim_log, re.escape(test.top_filename.rsplit('/', 1)[-1]))

test.passes()
