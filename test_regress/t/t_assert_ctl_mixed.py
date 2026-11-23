#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import json

import vltest_bootstrap

test.scenarios('vlt_all')

test.compile(verilator_flags2=[
    '--binary', '--assert', '--stats', '--dumpi-tree 3', '--dumpi-tree-json 3', '--no-json-ids',
    '--debug-emitv'
], threads=2 if test.vltmt else 1)

test.execute()

# Mixed routes retain their concrete caller identities until scoping consumes the plan.
seen = set()
for filename in test.glob_some(test.obj_dir + "/*.tree.json"):
    with open(filename, encoding='utf-8') as fh:
        pending = [json.load(fh)]
    while pending:
        node = pending.pop()
        if isinstance(node, list):
            pending.extend(node)
        elif isinstance(node, dict):
            kind = node.get('type')
            if kind == 'ASSERTCTLCALLER':
                if not node.get('anchorp'):
                    test.error('Assertion caller JSON is missing its anchor')
                if node.get('parentp'):
                    seen.add('child_caller')
                seen.add(kind)
            elif kind == 'ASSERTCTLCALLERREF':
                if not node.get('callerp'):
                    test.error('Assertion caller membership JSON is missing its occurrence')
                seen.add(kind)
            elif kind == 'ASSERTCTLPLAN':
                if not node.get('setsp'):
                    test.error('Assertion plan JSON is missing its target sets')
                seen.add(kind)
            elif kind == 'ASSERTCTLTARGETSET':
                if node.get('targetsp'):
                    seen.add(kind)
            elif kind == 'ASSERTCTLAPPLY' and node.get('planp'):
                seen.add('planned_apply')
            pending.extend(node.values())
required = {
    'ASSERTCTLCALLER', 'ASSERTCTLCALLERREF', 'ASSERTCTLPLAN', 'ASSERTCTLTARGETSET', 'child_caller',
    'planned_apply'
}
if not required <= seen:
    test.error('Missing assertion-control JSON metadata: ' + str(sorted(required - seen)))

# Route metadata is dumped as AST, not emitted as Verilog.
for filename in test.glob_some(test.obj_dir + "/*.tree.v"):
    test.file_grep_not(filename, r'assertion control target at depth|ASSERTCTLCALLER|ASSERTCTLPLAN')

test.passes()
