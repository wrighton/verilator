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

if not test.have_solver:
    test.skip('No constraint solver installed')

test.compile(verilator_flags2=['--binary'])

def constraint_setup(class_name):
    pattern = rf'^void [^\n]*{class_name}::__VnoInFunc_c_setup_constraint\([^)]*\)\s*\{{(.*?)^\}}'
    bodies = []
    for filename in test.glob_some(test.obj_dir + '/' + test.vm_prefix + '__Classes*.cpp'):
        bodies.extend(re.findall(pattern, test.file_contents(filename), re.MULTILINE | re.DOTALL))
    if len(bodies) != 1:
        test.error(f'Expected one constraint setup body for {class_name}')
    return bodies[0]


# A staged wide range takes one thread RNG draw per call.
if len(re.findall(r'\bVL_RANDOM_Q\s*\(', constraint_setup('DistLegacyWide'))) != 1:
    test.error('Staged wide DIST must take one thread RNG draw')

run_flags = ['+verilator+wno+unsatconstr+1']
test.execute(all_run_flags=run_flags)
# The ordinary distribution cases should finish without sampling diagnostics.
test.file_grep_not(test.obj_dir + '/vlt_sim.log', r'DIST weighting limited:')

# Sparse feasible buckets may legitimately run out of uniform points.
test.execute(all_run_flags=run_flags + ['+dist_point_cases'])
# The sparse point cases must exercise the limited-sampling diagnostic.
test.file_grep(test.obj_dir + '/vlt_sim.log',
               r'DIST weighting limited: no uniform point found in the selected bucket')

test.passes()
