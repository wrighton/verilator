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

test.compile()


def run(name, expect, flags=None, tamper_at=None, regexp=r'\(set-logic '):
    solver_log = test.obj_dir + '/solver_' + name + '.log'
    env = ''
    if tamper_at:
        env = ('VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
               'TAMPER=unknown_once TAMPER_AT=' + str(tamper_at))
    test.execute(logfile=test.obj_dir + '/sim_' + name + '.log',
                 all_run_flags=['+verilator+solver+file+' + solver_log] + (flags or []),
                 run_env=env)
    test.file_grep_count(solver_log, regexp, expect)


# Each of the 50 calls of three phases sets the logic once, after the session's opening check
run('keep', 1 + 50)

# Status 4 answers the first call's first trial, after the opening check, the soft check
# and the base's check. Unknown rebuilds that phase, and the next phase builds a fresh base.
run('unknown_trial', 1 + 50 + 2, tamper_at=4)

# The solver sampler seeds each phase, so every phase builds its base
run('sampler', 1 + 50 * 3, flags=['+verilator+rand+sampler+solver'])

# Each trial is one scope. Every k phase takes its first trial. The len phase is tried 32
# times in the first call, and again in the call after 128 calls without trials
run('narrow_129', 129 + 32, flags=['+narrow=129'], regexp=r'\(push 1\)')
run('narrow_130', 130 + 32 * 2, flags=['+narrow=130'], regexp=r'\(push 1\)')

# 300 calls whose len trials all fit, one trial each for k and len, then 100 calls whose
# len trials almost never fit. Halving the counts every 256 trials makes only 20 of the
# latter pay 32 len trials; without it, all 100 would
run('decay', 300 * 2 + 100 + 20 * 32, flags=['+decay'], regexp=r'\(push 1\)')

test.passes()
