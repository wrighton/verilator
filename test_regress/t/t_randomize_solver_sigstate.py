#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import os
import platform
import signal
import sys

import vltest_bootstrap

test.scenarios('vlt')
test.top_filename = "t/t_randomize_solver_fault.v"

if not test.have_solver:
    test.skip("No constraint solver installed")
if os.name != 'posix' or not hasattr(signal, 'SIGPIPE'):
    test.skip("No POSIX SIGPIPE on this platform")

test.compile(v_flags2=["t/t_randomize_solver_sigstate_c.cpp"] +
             (["-LDFLAGS -ldl"] if platform.system() == "Linux" else []),
             verilator_flags2=['-fno-constraint-fast'])

# The fixture sets each SIGPIPE state before the model runs.
wrapper = 'VERILATOR_SOLVER="' + sys.executable + ' ' + test.t_dir + '/randomize_solver_tamper.py" '

for state in ('blocked', 'pending', 'handler', 'ignored'):
    logfile = test.obj_dir + '/sim_' + state + '.log'
    latch = test.obj_dir + '/' + state + '.latch'
    if os.path.exists(latch):
        os.unlink(latch)
    test.execute(logfile=logfile,
                 run_env=wrapper + 'TAMPER=close_stdin_at TAMPER_AT=1 TAMPER_ONCE="' + latch +
                 '" SIGPIPE_STATE=' + state)
    test.file_grep(logfile, r'NPASS=(\d+)', 11)
    test.file_grep(logfile, r'Solver died or replied unreadably')
    test.file_grep(logfile, r'SIGPIPE state kept: ' + state)
    test.file_grep(logfile, r'Forwarded send before signal setup')

# These errors must follow the same failure/restart path as the original write().
for fault, message in (('eio', 'Input/output error'), ('eintr', 'Interrupted system call'),
                       ('epipe', 'Broken pipe')):
    logfile = test.obj_dir + '/sim_' + fault + '.log'
    test.execute(logfile=logfile,
                 run_env=wrapper + 'TAMPER=none SIGPIPE_STATE=blocked SOCKET_FAULT=' + fault)
    test.file_grep(logfile, r'write: ' + message)
    test.file_grep(logfile, r'NPASS=(\d+)', 11)
    test.file_grep(logfile, r'Socket send fault injected once: ' + fault)
    test.file_grep(logfile, r'SIGPIPE state kept: blocked')

# Shorten the actual send while retaining its flags, including on non-Linux hosts.
logfile = test.obj_dir + '/sim_short.log'
test.execute(logfile=logfile,
             run_env=wrapper + 'TAMPER=none SIGPIPE_STATE=blocked SOCKET_FAULT=short ')
test.file_grep(logfile, r'NPASS=(\d+)', 12)
test.file_grep(logfile, r'Short socket sends injected: ([1-9][0-9]*)')
test.file_grep(logfile, r'SIGPIPE state kept: blocked')

# A failure to create the request stream disables the solver, like pipe() did.
setup_faults = ['socketpair']
if 'SIGPIPE suppression: SO_NOSIGPIPE' in test.file_contents(logfile):
    setup_faults.append('sockopt')
for fault in setup_faults:
    logfile = test.obj_dir + '/sim_setup_' + fault + '.log'
    test.execute(logfile=logfile,
                 run_env=wrapper + 'TAMPER=none SIGPIPE_STATE=blocked SOCKET_FAULT=' + fault)
    test.file_grep(logfile, r'NPASS=(\d+)', 0)
    test.file_grep(logfile, r'Unable to communicate with SAT solver')
    test.file_grep(logfile, r'Socket setup fault injected once: ' + fault)
    test.file_grep(logfile, r'SIGPIPE state kept: blocked')

test.passes()
