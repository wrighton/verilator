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

test.compile(verilator_flags2=['-fno-constraint-fast'])

solver_log = test.obj_dir + '/solver.log'
test.execute(
    all_run_flags=['+verilator+rand+sampler+default', '+verilator+solver+file+' + solver_log])

# Spreading starts, then stops at the work allowance before the single-bit parts that
# finishing would need (an unlimited run pins every value down to them).
contents = test.file_contents(solver_log)
pin = r'^\s*\(assert\s+\(=\s+__Va\d+\s+'
if not re.search(pin, contents, re.MULTILINE):
    test.error('Expected spreading to pin values')
bit = r'\((?:not\s+\()?=\s+\(\(_\s+extract\s+(\d+)\s+\1\s*\)'
if re.search(pin + bit, contents, re.MULTILINE):
    test.error('Expected spreading to stop before single-bit parts')


def literal(text):
    """Value of a #x, #b or (_ bvN W) literal"""
    if text.startswith('#x'):
        return int(text[2:], 16)
    if text.startswith('#b'):
        return int(text[2:], 2)
    return int(re.match(r'\(_\s+bv(\d+)', text).group(1))


# The written value is the one from the last model read.
models = re.findall(r'^<[^\n]*\(pick\s+(#x[0-9a-fA-F]+|#b[01]+|\(_\s+bv\d+\s+\d+\))\s*\)',
                    contents, re.MULTILINE)
written = test.file_grep(test.obj_dir + '/vlt_sim.log', r'^Pin-budget pick (\d+)$')
if not models or not written or literal(models[-1]) != int(written[0]):
    test.error('Pin-budget value differs from the last model read')
# A completed weighted draw must not report a sampling cut.
test.file_grep_not(test.obj_dir + '/vlt_sim.log', r'DIST weighting limited:')

test.passes()
