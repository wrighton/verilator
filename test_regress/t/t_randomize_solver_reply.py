#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt')

if not test.have_solver:
    test.skip("No constraint solver installed")

test.compile(verilator_flags2=['-fno-constraint-fast'])

# 16 randomize calls; each entry names the reply the solver mangles
runs = [
    ('bad_base', 1, 15),  # a base character that is not b, o, x or h
    ('bad_digits', 1, 15),  # digits outside the stated base are not a number
    ('bad_index', 1, 15),  # a malformed array select index
    ('bad_value', 1, 15),  # a value with no base must not commit the earlier one
    ('bad_value', 4, 16),  # an unusable value in the reply to a spreading query
    ('bare_hash', 1, 15),  # a value that is only "#"
    ('bin_literals', 1, 16),  # every literal, select indices too, in binary
    ('binary', 1, 16),  # binary values
    ('bv_digits', 1, 15),  # an indexed literal of non-decimal digits
    ('bv_long', 1, 15),  # an indexed literal of more digits than its width allows
    ('bv_overflow', 1, 15),  # an indexed literal whose value does not fit its width
    ('bv_sort', 1, 15),  # an indexed literal of another width than the variable
    ('bv_spaced', 1, 16),  # indexed literals split by tabs and newlines
    ('core_junk', 1, 16),  # garbage opens the core reply, then the pipe closes
    ('crlf', 1, 16),  # CRLF line endings
    ('diversity_model', 2, 16),  # a diversity round answers with an unusable value
    ('dup_model', 1, 15),  # the same variable answered twice
    ('err_assume', 1, 16),  # error in place of the unsat assumptions
    ('err_core', 1, 16),  # error in place of the unsat core
    ('err_extra', 4, 15),  # error replying to a soft constraint, ahead of the relaxation status
    ('err_marker', 4, 15),  # a later error whose text holds a marker-like line; one call fails
    ('err_multiline', 2, 15),  # solver rejects a command with an error spanning two lines
    ('err_once', 2, 15),  # solver rejects a command instead of answering
    ('err_once', 9, 16),  # a rejected phase diversity round still lets the call pass
    ('err_phase', 1, 15),  # error in place of an intermediate phase value reply
    ('err_reply', 1, 15),  # error in place of an S-expression reply
    ('err_reply', 5, 16),  # error in place of the reply to a spreading query
    ('err_trunc', 2, 0),  # unterminated error, then the pipe closes
    ('err_unbal', 2, 15),  # a rejection error closing more parens than it opens
    ('err_unbal_cont', 2, 15),  # a rejection error with the extra paren on a continuation line
    ('garbage_assume', 1, 16),  # a bare word in place of the unsat assumptions
    ('garbage_model', 1, 15),  # half-valid model must not reach the variables
    ('garbage_status', 2, 15),  # a word that is not a status
    ('garbage_status', 15, 15),  # a phased check-sat that does not answer with a status
    ('high_digit', 1, 15),  # a digit legal for some base but not the stated one
    ('indent', 1, 16),  # leading whitespace before every reply
    ('low_digit', 1, 15),  # a character below any digit or letter
    ('model_trunc', 1, 0),  # unterminated model, then the pipe closes
    ('model_trunc', 4, 15),  # unterminated reply to a spreading query, then the pipe closes
    ('multiline', 1, 16),  # S-expression split one token per line
    ('no_digits', 1, 15),  # a base marker with no digits after it
    ('octal', 1, 16),  # octal values
    ('oor_assume', 1, 16),  # unsat assumptions naming only an out-of-range literal
    ('phase_model', 1, 15),  # error in place of the final phased model
    ('phase_trunc', 1, 12),  # unterminated phase value reply, then the pipe closes
    ('phase_trunc', 2, 12),  # the same in a phase diversity round, after which the call fails
    ('select_arity', 1, 15),  # an element of a one-dimensional array with two indices
    ('select_carry', 1, 15),  # an indexed index of 2^32, whose low bits name q[0]
    ('select_digit', 1, 15),  # a select with a bare digit after its index
    ('select_dup', 1, 15),  # one element answered twice, in two notations
    ('select_empty', 1, 15),  # a select of an array with no element
    ('select_extra', 1, 15),  # a select with a term after its index
    ('select_lead', 1, 15),  # a select with a bare digit before its index
    ('select_narrow', 1, 15),  # an index narrower than its sort
    ('select_octal', 1, 15),  # a select with an octal index of another width
    ('select_prefix', 1, 15),  # a misspelled select operator
    ('select_scalar', 1, 15),  # a select of a variable that is not an array
    ('select_unknown', 1, 15),  # an index within its sort naming no element
    ('select_whole', 1, 15),  # a whole array answered as one value
    ('select_wide', 1, 15),  # an index wider than its sort, which must not alias q[0]
    ('short_model', 1, 15),  # a model missing a requested variable is not a model
    ('success', 1, 16),  # print-success echo ahead of every reply
    ('unknown_once', 2, 15),  # unknown answers one check-sat
    ('unknown_once', 9, 16),  # unknown answers a spreading check
    ('unknown_twice', 2, 14),  # both the Packet hard check and Softy soft check must fail
    ('unknown_var', 1, 15),  # a variable that was never requested
    ('unknown_var', 4, 16),  # a spreading query answered with too many values
    ('unsupported_once', 2, 15),  # command not supported, so no status ever comes
    ('upper_hex', 1, 16),  # uppercase hex digits
    ('value_digit', 1, 15),  # a value with a bare digit after it
    ('value_lead', 1, 15),  # a value with a bare digit before it
    ('value_narrow', 1, 15),  # a binary value narrower than its variable
    ('value_wide', 1, 15),  # a hex value wider than its variable
]

for mode, at, npass in runs:
    logfile = test.obj_dir + '/sim_' + mode + '_' + str(at) + '.log'
    test.execute(logfile=logfile,
                 run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
                 'TAMPER=' + mode + ' TAMPER_AT=' + str(at))
    test.file_grep(logfile, r'NPASS=(\d+)', npass)

# An array with no element has no element a select can name
test.file_grep(test.obj_dir + '/sim_select_empty_1.log',
               r"Unable to parse solver's response: invalid array index")

# Every literal, select indices too, as an indexed (_ bvX n) literal. The blocking clauses
# show the UniGen2 cell enumeration read these replies too, rather than giving up.
logfile = test.obj_dir + '/sim_bv_literals.log'
solver_log = test.obj_dir + '/solver_bv_literals.log'
test.execute(logfile=logfile,
             all_run_flags=['+verilator+solver+file+' + solver_log],
             run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
             'TAMPER=bv_literals')
test.file_grep(logfile, r'NPASS=(\d+)', 16)
test.file_grep(solver_log, r'^  \(assert \(not \(and .*\(= \(select q #x00000000\) +#b[01]+\)')

# The first UniGen2 sampler reply, for Packet's second call. The replies before it answer
# the first calls' solves and diversity rounds, so their count depends on the solver's models:
# the injected reply must be the one right after the sampler's push and get-value, else
# this case does not test the sampler. A value of the wrong width must not reach a
# blocking clause, and the call still passes.
logfile = test.obj_dir + '/sim_bsat_narrow.log'
solver_log = test.obj_dir + '/solver_bsat_narrow.log'
test.execute(logfile=logfile,
             all_run_flags=['+verilator+solver+file+' + solver_log],
             run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
             'TAMPER=value_narrow TAMPER_AT=13')
test.file_grep(logfile, r'NPASS=(\d+)', 16)
test.file_grep(
    solver_log, r'^  \(push 1\)\n  \(check-sat\)\n< sat\n  \(get-value \( a b\)\)\n'
    r'< \(\(a #b0\) \(b #x12\)\)\n  \(pop 1\)$')
test.file_grep_not(solver_log, r'\(= a +#b0\)')

# 4 randomize calls through the diversity pin rounds, alone, from a fixed seed. A round
# the solver leaves unsettled keeps the base solution, so every call still passes; the
# count of check-sat-assuming rounds shows where each call's rounds stopped.
# Status 1 answers the check-sat sent when the session opens; statuses 2 and 3 are the
# soft relaxation and the base check-sat of call 1. To re-derive a TAMPER_AT, log the
# untampered +MODE=pins conversation and count the replies its mode counts.
pin_runs = [
    # Untampered: calls 1 to 4 each settle after 4 rounds: the pin of the variable conflicts,
    # and so does its check of whether it can change at all
    (None, 0, 16),
    # Status 4: the first pin round of call 1, answered unknown, so call 1 checks only the
    # base solution again
    ('unknown_once', 4, 14),
    # Unsat-assumptions reply 1: the first pin round of call 1, an error leaving no core
    ('err_assume', 1, 14),
    # Unsat-assumptions reply 1: the first pin round of call 1, naming only literals out of
    # range
    ('oor_assume', 1, 14),
    # Unsat-assumptions reply 1 on: every core names __Va0, which each call drops first anyway;
    # in the round checking whether it can change, __Va0 is no longer one of the literals, which
    # ends the rounds as untampered
    ('stale_assume', 1, 16),
]

for mode, at, nrounds in pin_runs:
    logfile = test.obj_dir + '/sim_pins_' + str(mode) + '.log'
    solver_log = test.obj_dir + '/solver_pins_' + str(mode) + '.log'
    test.execute(logfile=logfile,
                 all_run_flags=['+MODE=pins', '+verilator+solver+file+' + solver_log],
                 run_env=('VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
                          'TAMPER=' + mode + ' TAMPER_AT=' + str(at)) if mode else '')
    test.file_grep(logfile, r'NPASS=(\d+)', 4)
    test.file_grep_count(solver_log, r'^  \(check-sat-assuming', nrounds)

# 20 randomize calls of a wide class, alone, with a solver that does not support
# check-sat-assuming
test.execute(logfile=test.obj_dir + '/sim_wide_csa.log',
             all_run_flags=['+MODE=wide'],
             run_env='VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
             'TAMPER=csa_unsupported ')

# Check compatible soft constraints in both solve owners, also after a chunk was kept.
for phased in (0, 1):
    for kept in (0, 1):
        soft_runs = [('none', 0, 1), ('unknown_once', 2, 0), ('unsupported_once', 2, 0)]
        if kept:
            # Status 3 kept the highest-priority soft; status 4 checks the next one.
            soft_runs.append(('unknown_once', 4, 0))
        for mode, at, expected in soft_runs:
            tag = str(phased) + '_' + str(kept) + '_' + mode + '_' + str(at)
            test.execute(logfile=test.obj_dir + '/sim_soft_' + tag + '.log',
                         all_run_flags=['+MODE=soft_unknown', '+PHASED=' + str(phased),
                                        '+KEPT=' + str(kept), '+EXPECT=' + str(expected)],
                         run_env=('VERILATOR_SOLVER="' + test.t_dir +
                                  '/randomize_solver_tamper.py" TAMPER=' + mode +
                                  ' TAMPER_AT=' + str(at)) if mode != 'none' else '')

# 4 randomize calls with a variable whose rand_mode is off: an unusable value for it fails
# the call even though it is not written
for mode, npass in [(None, 4), ('frozen_value', 3)]:
    logfile = test.obj_dir + '/sim_frozen_' + str(mode) + '.log'
    test.execute(logfile=logfile,
                 all_run_flags=['+MODE=frozen'],
                 run_env=('VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
                          'TAMPER=' + mode + ' TAMPER_AT=1') if mode else '')
    test.file_grep(logfile, r'NPASS=(\d+)', npass)

# 8 phased randomize calls, alone, from a fixed seed. TAMPER_AT counts the phase value
# replies of the first layer of Phased or PhasedArr: 1 is the first call's, 2 the diversity
# round's that follows it. A phase value reply is pinned back to the solver, so one that does
# not answer each requested term once with a value of its sort fails the call; an unusable
# diversity reply keeps the values before it.
phased_runs = [
    (None, 0, 8),
    ('phase_bare', 1, 7),  # a pair that is not in a list
    ('phase_dup', 1, 7),  # the same variable answered twice
    ('phase_elem_bin', 2, 8),  # elements named with binary indices are the same elements
    ('phase_elem_dup', 1, 7),  # one element answered twice, in two notations
    ('phase_elem_h', 1, 7),  # element indices in #h notation
    ('phase_elem_other', 1, 7),  # an index naming no element, in place of a requested one
    ('phase_hex_h', 2, 8),  # a diversity value that is not an SMT-LIB literal
    ('phase_junk', 1, 7),  # a value that is not a literal
    ('phase_junk', 2, 8),  # the same in a diversity reply
    ('phase_narrow', 1, 7),  # a value narrower than its variable
    ('phase_narrow', 2, 8),  # the same in a diversity reply
    ('phase_partial', 2, 8),  # a diversity reply applies none of its values if one is unusable
    ('phase_short', 1, 7),  # a reply answering nothing
    ('phase_var', 1, 7),  # a variable of a later layer, in place of the requested one
    ('phase_whole_asarray', 2, 8),  # an array value that is neither a constant nor a store
    ('phase_whole_bv', 1, 8),  # indexed literals inside an array value
    ('phase_whole_bv_bad', 2, 8),  # a malformed indexed literal inside an array value
    ('phase_whole_bv_open', 2, 8),  # an indexed literal left open, bound in a let
    ('phase_whole_chain', 1, 8),  # nested lets as deep as solvers write them are a value
    ('phase_whole_compact', 1, 8),  # an array value spaced tightly is still one
    ('phase_whole_const_open', 2, 8),  # a constant array with a term after its sort
    ('phase_whole_deep', 2, 8),  # lets nested deeper than the reader's bound
    ('phase_whole_elem', 2, 8),  # an array with no element answered with narrower elements
    ('phase_whole_extra', 2, 8),  # a constant array with an extra term
    ('phase_whole_extra_store', 2, 8),  # a store with an extra term
    ('phase_whole_index', 2, 8),  # a store into an array with an index narrower than its sort
    ('phase_whole_junk', 2, 8),  # an array with no element answered by a non-array value
    ('phase_whole_let', 1, 8),  # an array value given by a let
    ('phase_whole_let_dup', 2, 8),  # a let binding one name twice
    ('phase_whole_let_empty', 2, 8),  # a let binding nothing
    ('phase_whole_let_free', 2, 8),  # a let binding a name to a term that is not a value
    ('phase_whole_let_lit', 2, 8),  # a let name that is a literal
    ('phase_whole_let_nul', 2, 8),  # a let name holding a NUL
    ('phase_whole_let_num', 2, 8),  # a let name that is a numeral
    ('phase_whole_let_quoted', 2, 8),  # a quoted let name, which is not supported
    ('phase_whole_let_reserved', 2, 8),  # a let name that is a reserved word
    ('phase_whole_let_seq', 2, 8),  # a let whose binding refers to another of its bindings
    ('phase_whole_let_sort', 2, 8),  # a let whose value is a bit-vector, not an array
    ('phase_whole_let_spare', 1, 8),  # a valid binding left unused is legal
    ('phase_whole_let_unused', 2, 8),  # a let with an unused binding that is not a value
    ('phase_whole_lines', 1, 8),  # an array value over several lines is still one
    ('phase_whole_shadow_bv', 2, 8),  # a let naming bv0, so (_ bv0 5) is no literal
    ('phase_whole_shadow_const', 2,
     8),  # a let naming const, so (as const ...) is no constant array
    ('phase_whole_shadow_store', 2, 8),  # a let naming store, so (store ...) is no store
    ('phase_whole_select', 1, 7),  # an element of an array that has none
    ('phase_whole_sort', 2, 8),  # an array with no element answered with another index sort
    ('phase_whole_store', 1, 8),  # a store into a constant array is an array value
    ('phase_whole_store_let', 1, 8),  # a store into an array a let names
    ('phase_whole_trail', 2, 8),  # an array value followed by another term
]

for mode, at, npass in phased_runs:
    logfile = test.obj_dir + '/sim_phased_' + str(mode) + '_' + str(at) + '.log'
    solver_log = test.obj_dir + '/solver_phased_' + str(mode) + '_' + str(at) + '.log'
    test.execute(logfile=logfile,
                 all_run_flags=['+MODE=phased', '+verilator+solver+file+' + solver_log],
                 run_env=('VERILATOR_SOLVER="' + test.t_dir + '/randomize_solver_tamper.py" ' +
                          'TAMPER=' + mode + ' TAMPER_AT=' + str(at)) if mode else '')
    test.file_grep(logfile, r'NPASS=(\d+)', npass)

# Pins name each element as requested, whichever notation the reply used
test.file_grep(test.obj_dir + '/solver_phased_phase_elem_bin_2.log',
               r'^  \(assert \(= \(select w #x00000000\) #b00011\)\)')
# A rejected value is never pinned
test.file_grep_not(test.obj_dir + '/solver_phased_phase_junk_2.log', r'\(= x junk\)')
test.file_grep_not(test.obj_dir + '/solver_phased_phase_var_1.log', r'\(= y #x5\)')
test.file_grep(test.obj_dir + '/sim_phased_phase_var_1.log',
               r"Unable to parse solver's response: unknown variable")
for mode in ['phase_dup', 'phase_elem_dup']:
    test.file_grep(test.obj_dir + '/sim_phased_' + mode + '_1.log',
                   r"Unable to parse solver's response: repeated variable")
test.file_grep(test.obj_dir + '/sim_phased_phase_bare_1.log',
               r"Unable to parse solver's response: invalid S-expression")
test.file_grep(test.obj_dir + '/sim_phased_phase_short_1.log',
               r"Unable to parse solver's response: incomplete model")
for mode in [
        'phase_whole_deep', 'phase_whole_let_dup', 'phase_whole_let_empty',
        'phase_whole_let_quoted', 'phase_whole_let_reserved', 'phase_whole_trail'
]:
    test.file_grep(test.obj_dir + '/sim_phased_' + mode + '_2.log',
                   r"Unable to parse solver's response: invalid value")

test.passes()
