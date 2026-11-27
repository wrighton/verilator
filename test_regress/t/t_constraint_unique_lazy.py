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
    test.skip("No constraint solver installed")

test.compile()


def solver_stats(n):
    """Run with n elements, and return the solver checks and the element pairs that a
    'distinct' over the large array asks to differ"""
    log = test.obj_dir + "/solver_" + str(n) + ".log"
    test.execute(all_run_flags=['+n=' + str(n), '+verilator+solver+file+' + log],
                 logfile=test.obj_dir + "/sim_" + str(n) + ".log",
                 expect_filename=test.golden_filename)
    checks = 0
    pairs = 0
    with open(log, encoding="utf8") as fh:
        text = fh.read()
    checks = len(re.findall(r'^  \(check-sat', text, re.M))
    for term in re.findall(r'\(distinct((?: \(select qf [^)]*\))+)\)', text):
        args = term.count('(select')
        pairs += args * (args - 1) // 2
    # A small domain falls back to the whole 'distinct', after constraining equal elements
    test.file_grep(log, r'; unique fallback')
    test.file_grep(log, r'; unique refinement 1')
    # A fallback solves as the 'distinct' would from the start, after a solve without it that
    # stops spreading its values at the first conflict: a check, a spreading one, and one
    # keeping the values found
    segment = 0  # Checks since the last reset
    ended = 0  # Checks of the solve the last reset ended
    for line in text.splitlines():
        if line.startswith("  (check-sat"):
            segment += 1
        elif line == "  (reset)":
            ended = segment
            segment = 0
        elif line == "  ; unique fallback" and ended > 3:
            test.error(str(ended) + " solver checks before a fallback")
    return checks, pairs


checks_small, pairs_small = solver_stats(200)
if pairs_small > 200:
    test.error(str(pairs_small) + " pairs of elements asked to differ, of 200 elements")
checks_large, pairs_large = solver_stats(2000)
# The solver work for the large array grows no faster than its elements: as many checks
# whatever its size, and no more pairs of elements asked to differ than it has elements
if checks_large != checks_small:
    test.error("Checks " + str(checks_large) + " with 2000 elements, " + str(checks_small) +
               " with 200")
if pairs_large > 2000:
    test.error(str(pairs_large) + " pairs of elements asked to differ, of 2000 elements")

test.passes()
