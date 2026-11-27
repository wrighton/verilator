#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os
import re

import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile()


def run(tag, tamper, flags=None, once=True):
    logfile = test.obj_dir + '/sim_' + tag + '.log'
    latch = test.obj_dir + '/' + tag + '.latch'
    if os.path.exists(latch):
        os.unlink(latch)
    # Acting once in the run, the restarted solver serves the later calls
    test.execute(logfile=logfile,
                 all_run_flags=flags or [],
                 run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
                 tamper + (' TAMPER_ONCE="' + latch + '" ' if once else ' '))
    return logfile


def spread_failed(logfile, died=False, npass=4):
    test.file_grep(logfile, r'NPASS=(\d+)', npass)
    if died:
        test.file_grep(logfile, r'Solver died or replied unreadably while spreading the solution')
    else:
        test.file_grep(logfile, r'Solver failed while spreading the solution')
    # No warning claims a call returned 0, as each returned 1
    test.file_grep_not(logfile, r'randomize\(\) return(s|ed) 0')


# Exits with 101, as z3 does out of memory, at the first spreading check after the solution,
# which randomize() returns
spread_failed(run('spread', 'TAMPER=die_status_at TAMPER_AT=3 TAMPER_EXIT=101'), True)

# Likewise at every spreading check, so each call returns its solution, and the solver is not
# given up. After each break the object does not spread for 1, 2, 4, then 8 calls, so of its
# 16 calls only calls 1, 3, 6 and 11 spread, and then a copy of it, which spreads afresh.
log = test.obj_dir + '/solver_spread_every.log'
logfile = run('spread_every',
              'TAMPER=die_assuming TAMPER_EXIT=101',
              ['+wide', '+calls=16', '+copy', '+verilator+solver+file+' + log],
              once=False)
spread_failed(logfile, True, 17)
test.file_grep_not(logfile, r'Solver failed repeatedly')
with open(log, encoding="utf8") as fh:
    spreads = sum(1 for line in fh if line.startswith('  (check-sat-assuming'))
if spreads != 5:
    test.error(str(spreads) + " calls spread, not 5")

# Once, after which spreading resumes, so the later calls' values vary again
logfile = run('spread_recover', 'TAMPER=die_assuming TAMPER_EXIT=101', ['+wide', '+calls=16'])
spread_failed(logfile, True, 16)
with open(logfile, encoding="utf8") as fh:
    distinct = int(re.search(r'DISTINCT=(\d+)', fh.read()).group(1))
if distinct < 12:
    test.error("Only " + str(distinct) + " distinct values in the 15 calls after the break")

# UniGen2 sampling dying at its first check-sat-assuming, from the second call on: the
# pauses keep it to calls 2, 4, 7 and 12 of 16
log = test.obj_dir + '/solver_sample_every.log'
logfile = run('sample_every',
              'TAMPER=die_assuming TAMPER_MATCH=__Vd TAMPER_EXIT=101',
              ['+sampled', '+calls=16', '+verilator+solver+file+' + log],
              once=False)
test.file_grep(logfile, r'NPASS=(\d+)', 16)
test.file_grep(logfile, r'Solver died or replied unreadably while spreading the solution')
with open(log, encoding="utf8") as fh:
    samples = sum(1 for line in fh if line.startswith('  (check-sat-assuming (__Vd'))
if samples != 4:
    test.error(str(samples) + " calls sampled, not 4")

# A spreading model naming an unknown variable
logfile = run('spread_model', 'TAMPER=unknown_var TAMPER_AT=2')
spread_failed(logfile)
test.file_grep(logfile, r'Unable to parse solver.s response: unknown variable')

# Exits with 101 within the model, so that randomize() returns 0
logfile = run('model', 'TAMPER=model_trunc TAMPER_AT=1 TAMPER_EXIT=101')
test.file_grep(logfile, r'NPASS=(\d+)', 3)
test.file_grep(logfile, r'Solver died or replied unreadably, so this randomize\(\) returned 0')
test.file_grep_not(logfile, r'while spreading')

# Spreading the first phase: its check rejected, or the values of its solution
spread_failed(run('phase_check', 'TAMPER=err_once TAMPER_AT=3', ['+phased']))
spread_failed(run('phase_values', 'TAMPER=err_reply TAMPER_AT=2', ['+phased']))
# Spreading the last phase
spread_failed(run('phase_last', 'TAMPER=die_status_at TAMPER_AT=5', ['+phased']), True)

# A first phase spreading check answered by an unterminated error, and then no reply, so
# that randomize() returns 0
logfile = run('phase_trunc', 'TAMPER=err_trunc TAMPER_AT=3', ['+phased'])
test.file_grep(logfile, r'NPASS=(\d+)', 3)
test.file_grep(logfile, r'Solver did not answer with a status, so randomize\(\) returns 0')
test.file_grep_not(logfile, r'while spreading')

test.passes()
