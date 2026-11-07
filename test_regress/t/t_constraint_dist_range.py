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

test.scenarios('simulator')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()

test.execute()

if test.vlt:
    # The existing wide single-range case must evaluate its 64-bit offset once,
    # not once per wide word. Keep this check local to that constraint setup.
    setup_bodies = []
    for filename in test.glob_some(test.obj_dir + "/" + test.vm_prefix + "__Classes*.cpp"):
        setup_bodies.extend(
            re.findall(
                r"void [^\n]*DistSignedWide::__VnoInFunc_c_w_setup_constraint\([^)]*\)\s*\{(.*?)^\}",
                test.file_contents(filename),
                re.MULTILINE | re.DOTALL,
            ))
    if len(setup_bodies) != 1:
        test.error("Expected the wide dist constraint setup function")
    if len(re.findall(r"\bVL_RANDOM_Q\s*\(", setup_bodies[0])) != 1:
        test.error("Wide dist offset must consume one random draw")

test.passes()
