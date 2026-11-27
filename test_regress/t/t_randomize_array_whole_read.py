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

# The arrays are read only by element, which -fconstraint-scalar would declare by element
test.compile(verilator_flags2=['-fno-constraint-scalar'])


def reads(log):
    """Per (get-value) command of a solver log: the arrays it asks whole, and how many
    elements of each it asks by select"""
    commands = []
    with open(log, encoding="utf8") as fh:
        for line in fh:
            if not line.startswith("  (get-value ("):
                continue
            terms = []
            depth = 0
            for token in re.findall(r"\(|\)|[^\s()]+", line[len("  (get-value ("):]):
                if depth == 0 and token not in ("(", ")"):
                    terms.append(token)
                elif depth == 0 and token == "(":
                    terms.append("")
                if token == "(":
                    depth += 1
                elif token == ")":
                    depth -= 1
                elif depth == 1 and terms and terms[-1] in ("", "select"):
                    terms[-1] += token if not terms[-1] else " " + token
            whole = {term for term in terms if term in ("d", "f", "q", "s")}
            elems = {}
            for term in terms:
                if term.startswith("select "):
                    elems[term.split()[1]] = elems.get(term.split()[1], 0) + 1
            commands.append((whole, elems))
    return commands


def whole_read(commands, name):
    return any(name in whole for whole, _ in commands)


def element_read(commands, name, size):
    """Whether a command asks every element of the array by select"""
    return any(elems.get(name, 0) == size for _, elems in commands)


solver_log = test.obj_dir + "/solver.log"
test.execute(all_run_flags=['+verilator+solver+file+' + solver_log])
commands = reads(solver_log)
# The large arrays are read whole, the small one by element
for name, size in (("d", 100), ("f", 100), ("q", 80)):
    if not whole_read(commands, name) or element_read(commands, name, size):
        test.error("Not read whole: " + name)
if whole_read(commands, "s") or not element_read(commands, "s", 10):
    test.error("Not read by element: s")

tamper = 'VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py"'
# (mode, reply asking d whole to act on, result, whether d is then read by element): a
# value of another form is read by element after it, the store forms as they are, and
# nothing is written when the read by element fails too or the reply answers d twice
rows = [
    ("whole_asarray", 2, "solved", True),
    ("whole_dup_let", 2, "solved", True),
    ("whole_error", 2, "solved", True),
    ("whole_lambda", 1, "solved", True),
    ("whole_narrow", 2, "solved", True),
    ("whole_chain", 2, "stores", False),
    ("whole_lets", 2, "stores", False),
    ("whole_let_scalar", 2, "stores", False),
    ("whole_let_alias", 2, "stores", False),
    ("whole_cycle", 2, "solved", True),
    ("whole_fail", 1, "failed", True),
    ("whole_twice", 1, "failed", False),
]
for mode, at, want, by_element in rows:
    log = test.obj_dir + "/solver_" + mode + ".log"
    test.execute(run_env=tamper + " TAMPER=" + mode + " TAMPER_AT=" + str(at),
                 all_run_flags=['+verilator+solver+file+' + log, '+want=' + want])
    commands = reads(log)
    if not whole_read(commands, "d") or element_read(commands, "d", 100) != by_element:
        test.error(mode + ": d read by element " + str(not by_element))

test.passes()
