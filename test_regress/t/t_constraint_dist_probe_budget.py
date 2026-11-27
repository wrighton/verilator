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

# Preserve one initial checkpoint through rejected probes, and prefer a final
# satisfying model read when the solver is still live at the cut.
sim_log = test.obj_dir + '/vlt_sim.log'
contents = test.file_contents(solver_log)
# Each model read: the free_value pair anywhere in one reply, continuation lines included.
literal = r'(#x[0-9a-fA-F]+|#b[01]+|\(_\s+bv\d+\s+\d+\))'
reads = []
for reply in re.finditer(r'(?:^<[^\n]*(?:\n|$))+', contents, re.MULTILINE):
    joined = ' '.join(re.sub(r'^<\s?', '', line) for line in reply.group(0).splitlines())
    pair = re.search(r'\(free_value\s+' + literal + r'\s*\)', joined)
    if pair:
        reads.append((reply.start(), pair.group(1)))
checks = list(re.finditer(r'^<\s*(sat|unsat|unknown)\s*$', contents, re.MULTILINE))
# Bucket probes use check-sat; spreading the other values afterwards uses check-sat-assuming.
rejected = list(re.finditer(r'^\s*\(check-sat\)\s*\n<\s*unsat\s*$', contents, re.MULTILINE))
if not rejected or sum(start < rejected[0].start() for start, _ in reads) != 1:
    test.error('Expected exactly one initial checkpoint before the rejected probes')
if any(rejected[0].start() < start < rejected[-1].end() for start, _ in reads):
    test.error('Rejected probes must not capture another checkpoint')
expected = reads[0]
if checks[-1].group(1) == 'sat':
    final = [read for read in reads if read[0] > checks[-1].end()]
    if len(final) != 1:
        test.error('Expected one final model read after the last satisfying check')
    expected = final[0]
written = test.file_grep(sim_log, r'^Probe-budget value (\d+)$')
if written:
    value = expected[1]
    if value.startswith('#x'):
        number = int(value[2:], 16)
    elif value.startswith('#b'):
        number = int(value[2:], 2)
    else:
        number = int(re.match(r'\(_\s+bv(\d+)', value).group(1))
    if number != int(written[0]):
        test.error('Probe-budget exhaustion changed the value from the last usable model')
# Verify this run exercised the intended probe-budget cut.
test.file_grep(sim_log, r'DIST weighting limited: sampling limit reached')

test.passes()
