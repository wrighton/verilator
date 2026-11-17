#!/usr/bin/env python3
# DESCRIPTION: Verilator: fake SMT solver wrapper for solver resilience tests
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3,
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#
# Forwards the SMT-LIB conversation to a real solver, tampering the replies.
#
# Input arguments from environment variables:
# TAMPER: bad_base | bad_digits | bad_index | bad_value | bare_hash | bin_literals
#         | binary | bv_digits | bv_literals | bv_long | bv_overflow | bv_sort | bv_spaced
#         | core_junk | crlf | csa_unsupported | die_at | die_status_at | diversity_model
#         | dup_model | err_assume | err_cell | err_core | err_extra | err_marker
#         | err_multiline | err_mute | err_once | err_phase | err_reply | err_trunc | err_unbal
#         | err_unbal_cont | frozen_value
#         | garbage_assume | garbage_at | garbage_model | garbage_status
#         | high_digit | indent | low_digit | model_trunc | multiline | mute_at
#         | no_digits | none | octal | oor_assume | phase_bare | phase_dup | phase_elem_bin
#         | phase_elem_dup | phase_elem_h | phase_elem_other | phase_hex_h | phase_junk
#         | phase_model | phase_narrow | phase_partial | phase_short | phase_trunc | phase_var
#         | phase_whole_asarray | phase_whole_bv | phase_whole_bv_bad | phase_whole_bv_open
#         | phase_whole_chain | phase_whole_compact | phase_whole_const_open | phase_whole_deep
#         | phase_whole_elem | phase_whole_extra | phase_whole_extra_store | phase_whole_index
#         | phase_whole_junk | phase_whole_let | phase_whole_let_dup | phase_whole_let_empty
#         | phase_whole_let_free | phase_whole_let_lit | phase_whole_let_nul | phase_whole_let_num
#         | phase_whole_let_quoted | phase_whole_let_reserved | phase_whole_let_seq
#         | phase_whole_let_sort | phase_whole_let_spare | phase_whole_let_unused
#         | phase_whole_lines | phase_whole_select | phase_whole_shadow_bv
#         | phase_whole_shadow_const | phase_whole_shadow_store | phase_whole_sort
#         | phase_whole_store | phase_whole_store_let | phase_whole_trail
#         | select_arity | select_carry | select_digit | select_dup | select_empty
#         | select_extra | select_lead | select_narrow | select_octal | select_prefix
#         | select_scalar | select_unknown | select_whole | select_wide
#         | short_model | stale_assume | success | unknown_once | unknown_twice
#         | unknown_var | unsat_recheck | unsupported_once | upper_hex | value_digit
#         | value_lead | value_narrow | value_wide
#   bad_base         - replace the Nth model reply with a base character that is not b, o, x or h
#   bad_digits       - replace the Nth model reply with one value holding digits outside its base
#   bad_index        - replace the first array model reply with a bad select index
#   bad_value        - replace the Nth model reply with one well-formed value lacking a base
#   bare_hash        - replace the Nth model reply with one value that is only "#"
#   bin_literals     - write every hex literal as the same-width binary one, as cvc5 does
#   binary           - replace the Nth model reply with binary values
#   bv_digits        - replace the Nth model reply with an indexed literal of non-decimal digits
#   bv_literals      - write every hex and binary literal as an indexed (_ bvX n) literal
#   bv_long          - replace the Nth model reply with an indexed literal of too many digits
#   bv_overflow      - replace the Nth model reply with an indexed literal too big for its width
#   bv_sort          - replace the Nth model reply with an indexed literal of another width
#   bv_spaced        - write every hex literal as an indexed one split by tabs and newlines
#   core_junk        - prepend garbage to the core reply and close the pipe
#   crlf             - end every line with CRLF
#   csa_unsupported  - answer every check-sat-assuming with unsupported
#   die_at           - kill the solver at the Nth model reply and exit, closing every pipe end
#   die_status_at    - kill the solver at the Nth status line and exit, closing every pipe end
#   diversity_model  - replace the Nth array model reply with one holding an unusable value
#   dup_model        - replace the Nth model reply with one answering a variable twice
#   err_assume       - replace the first unsat-assumptions reply with (error ...)
#   err_cell         - as err_extra, at the Nth status of the unigen2 sampler's first cell
#                      enumeration, counted from the first push scope opened after the
#                      estimate's last scope, the first one to find a solution and run out;
#                      it never acts when the estimate ends on a large space with no such scope
#   err_core         - replace the first unsat-core reply with (error ...)
#   err_extra        - send an (error ...) line ahead of the Nth status, as for a rejected
#                      earlier command; echo the runtime's marker quoted, as SMT-LIB 2.6 does
#   err_marker       - answer the Nth status with (error ...), then send a multiline (error ...)
#                      holding a line that is only the runtime's marker ahead of the next status
#   err_multiline    - answer the Nth status with an (error ...) split over two lines
#   err_mute         - answer the Nth status with (error ...), then close the reply pipe as mute_at
#   err_once         - answer the Nth status with one (error ...) line
#   err_phase        - replace the first phase value reply with (error ...)
#   err_reply        - replace the Nth S-expression reply with (error ...)
#   err_trunc        - answer the Nth status with an unterminated (error and close the pipe
#   err_unbal        - answer the Nth status with an error closing an extra paren
#   err_unbal_cont   - answer the Nth status with an error, the extra paren on a continuation line
#   frozen_value     - replace the Nth model reply with a bad value for a variable not written
#   garbage_assume   - answer the unsat assumptions with a non-S-expression word
#   garbage_at       - replace every Nth model reply with a non-S-expression line
#   garbage_model    - replace the Nth model reply with a partly valid one
#   garbage_status   - replace the Nth status with a word that is not a status
#   high_digit       - replace the Nth model reply with a digit valid only in a wider base
#   indent           - prepend whitespace to every reply line
#   low_digit        - replace the Nth model reply with a character below any digit or letter
#   model_trunc      - answer the Nth model with an unterminated reply and close the pipe
#   multiline        - split every S-expression reply one token per line
#   mute_at          - close the reply pipe at the Nth model reply but keep this wrapper running
#   no_digits        - replace the Nth model reply with a value whose base has no digits
#   none             - forward every reply unchanged
#   octal            - replace the Nth model reply with octal values
#   oor_assume       - answer the unsat assumptions with an out-of-range literal
#   phase_bare       - replace the Nth x phase value reply with a pair that is not in a list
#   phase_dup        - replace the Nth x phase value reply with x answered twice
#   phase_elem_bin   - replace the Nth e/w phase value reply with binary indices
#   phase_elem_dup   - replace the Nth e/w phase value reply with one element in two notations
#   phase_elem_h     - replace the Nth e/w phase value reply with #h indices
#   phase_elem_other - replace the Nth e/w phase value reply with an index naming no element
#   phase_hex_h      - replace the Nth x phase value reply with a value in #h notation
#   phase_junk       - replace the Nth x phase value reply with a value that is not a literal
#   phase_model      - replace the final phased model reply with (error ...)
#   phase_narrow     - replace the Nth x phase value reply with a value narrower than x
#   phase_partial    - replace the Nth e/w phase value reply with one whose last value is unusable
#   phase_short      - replace the Nth x phase value reply with one answering nothing
#   phase_trunc      - answer an unterminated phase value reply and close the pipe
#   phase_var        - replace the Nth x phase value reply with one naming the later layer's y
#   phase_whole_asarray - replace the Nth e/w phase value reply with a non-constant array form
#   phase_whole_bv   - replace the Nth e/w phase value reply with indexed literals in an array
#   phase_whole_bv_bad - replace the Nth e/w phase value reply with a bad indexed literal in it
#   phase_whole_bv_open - replace the Nth e/w phase value reply with an open indexed literal
#   phase_whole_chain - replace the Nth e/w phase value reply with 3000 nested lets
#   phase_whole_compact - replace the Nth e/w phase value reply with a whole array spaced tightly
#   phase_whole_const_open - replace the Nth e/w phase value reply with junk in a constant
#   phase_whole_deep - replace the Nth e/w phase value reply with lets 100000 deep
#   phase_whole_elem - replace the Nth e/w phase value reply with a whole array of narrow elements
#   phase_whole_extra - replace the Nth e/w phase value reply with a constant array of two elements
#   phase_whole_extra_store - replace the Nth e/w phase value reply with a store of an extra term
#   phase_whole_index - replace the Nth e/w phase value reply with a store of a narrow index
#   phase_whole_junk - replace the Nth e/w phase value reply with a whole array that is not one
#   phase_whole_let  - replace the Nth e/w phase value reply with a whole array in a let
#   phase_whole_let_dup - replace the Nth e/w phase value reply with a let binding one name twice
#   phase_whole_let_empty - replace the Nth e/w phase value reply with a let binding nothing
#   phase_whole_let_free - replace the Nth e/w phase value reply with a let bound to junk
#   phase_whole_let_lit - replace the Nth e/w phase value reply with a literal let name
#   phase_whole_let_nul - replace the Nth e/w phase value reply with a NUL in a let name
#   phase_whole_let_num - replace the Nth e/w phase value reply with a numeral let name
#   phase_whole_let_quoted - replace the Nth e/w phase value reply with a quoted let name
#   phase_whole_let_reserved - replace the Nth e/w phase value reply with a reserved let name
#   phase_whole_let_seq - replace the Nth e/w phase value reply with a let binding read in sequence
#   phase_whole_let_sort - replace the Nth e/w phase value reply with a let of a bit-vector
#   phase_whole_let_spare - replace the Nth e/w phase value reply with a binding left unused
#   phase_whole_let_unused - replace the Nth e/w phase value reply with a junk unused let binding
#   phase_whole_lines - replace the Nth e/w phase value reply with a whole array over three lines
#   phase_whole_select - replace the Nth e/w phase value reply with an element of e
#   phase_whole_shadow_bv - replace the Nth e/w phase value reply with a let naming bv0
#   phase_whole_shadow_const - replace the Nth e/w phase value reply with a let naming const
#   phase_whole_shadow_store - replace the Nth e/w phase value reply with a let naming store
#   phase_whole_sort - replace the Nth e/w phase value reply with a whole array of another sort
#   phase_whole_store - replace the Nth e/w phase value reply with a store into a whole array
#   phase_whole_store_let - replace the Nth e/w phase value reply with a store into a let
#   phase_whole_trail - replace the Nth e/w phase value reply with a term after a whole array
#   select_arity     - replace the Nth array model reply with a select of too many indices
#   select_carry     - replace the Nth array model reply with an indexed index of 2^width
#   select_digit     - replace the Nth array model reply with a select of an extra digit
#   select_dup       - replace the Nth array model reply with one element in two notations
#   select_empty     - replace the Nth array model reply with a select of an array with no element
#   select_extra     - replace the Nth array model reply with a select of an extra term
#   select_lead      - replace the Nth array model reply with a select of a digit before its index
#   select_narrow    - replace the Nth array model reply with an index narrower than its sort
#   select_octal     - replace the Nth array model reply with an octal index of another width
#   select_prefix    - replace the Nth array model reply with a misspelled select
#   select_scalar    - replace the Nth array model reply with a select of a scalar
#   select_unknown   - replace the Nth array model reply with an index naming no element
#   select_whole     - replace the Nth array model reply with a whole array answered as a value
#   select_wide      - replace the Nth array model reply with an index wider than the index's sort
#   short_model      - replace the Nth model reply with one omitting a requested variable
#   stale_assume     - answer every unsat assumptions reply from the Nth with the literal __Va0
#   success          - echo a print-success line before every reply
#   unknown_once     - answer the Nth status with unknown
#   unknown_twice    - answer two statuses with unknown
#   unknown_var      - replace the Nth model reply with one naming a variable never requested
#   unsat_recheck    - answer the status that follows an unsat with sat
#   unsupported_once - answer the Nth status with unsupported
#   upper_hex        - replace the Nth model reply with uppercase hex digits
#   value_digit      - replace the Nth model reply with an extra digit after a value
#   value_lead       - replace the Nth model reply with an extra digit before a value
#   value_narrow     - replace the Nth model reply with a value narrower than its variable
#   value_wide       - replace the Nth model reply with a value wider than its variable
# TAMPER_AT: reply index to act on (default 3)
# TAMPER_ONCE: file marking that the tamper already acted. The runtime restarts
#   a solver that died, which starts this wrapper again, so without the file a
#   mode acts once per solver rather than once per simulation.

# pylint: disable=C0103,C0114,consider-using-with

import os
import re
import shutil
import subprocess
import sys
import threading
import time
import types

mode = os.environ.get("TAMPER", "none")
at = int(os.environ.get("TAMPER_AT", "3"))
once = os.environ.get("TAMPER_ONCE", "")

# Modes acting on the TAMPER_AT'th status line rather than the Nth model reply
STATUS_MODES = ("die_status_at", "err_extra", "err_marker", "err_multiline", "err_mute",
                "err_once", "err_trunc", "err_unbal", "err_unbal_cont", "garbage_status",
                "unknown_once", "unknown_twice", "unsupported_once")
# Modes acting on the TAMPER_AT'th S-expression reply of any kind
REPLY_MODES = ("err_reply", )
# Modes acting on an array model reply, which arrives as (select ...) terms
SELECT_MODES = ("bad_index", "diversity_model", "select_arity", "select_carry", "select_digit",
                "select_dup", "select_empty", "select_extra", "select_lead", "select_narrow",
                "select_octal", "select_prefix", "select_scalar", "select_unknown", "select_whole",
                "select_wide")
# Modes acting on a status found from the push scopes of the commands
CELL_MODES = ("err_cell", )
# Modes acting on the status the solver sends after answering unsat
RECHECK_MODES = ("unsat_recheck", )
# phase_model acts on the final phased model; the others on any phase value reply
PHASE_MODES = ("err_phase", "phase_model", "phase_trunc")
# Modes replacing the Nth phase value reply of Phased's x layer or PhasedArr's e and w layer:
# (first line of the reply, what a final model of every layer also holds, replacement)
E5 = "(Array (_ BitVec 32) (_ BitVec 5))"
EW = " ((select w #x00000000) #b00011) ((select w #x00000001) #b00101))"
PHASE_VALUE_MODES = {
    "phase_bare": ("((x", "(y ", "(x #x1)"),
    "phase_dup": ("((x", "(y ", "((x #x1) (x #b0001))"),
    "phase_elem_bin": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000))"
                       " ((select w #b" + "0" * 32 + ") #b00011)"
                       " ((select w #b" + "0" * 31 + "1) #b00101))"),
    "phase_elem_dup":
    ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000))"
     " ((select w #x00000000) #b00011) ((select w #b" + "0" * 32 + ") #b00011))"),
    "phase_elem_h": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000))"
                     " ((select w #h00000000) #b00011) ((select w #h00000001) #b00101))"),
    "phase_elem_other": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000))"
                         " ((select w #x00000000) #b00011) ((select w #x00000002) #b00101))"),
    "phase_hex_h": ("((x", "(y ", "((x #h3))"),
    "phase_junk": ("((x", "(y ", "((x junk))"),
    "phase_narrow": ("((x", "(y ", "((x #b1))"),
    "phase_partial": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000))"
                      " ((select w #x00000000) #b10101) ((select w #x00000002) #b00101))"),
    "phase_short": ("((x", "(y ", "()"),
    "phase_var": ("((x", "(y ", "((y #x5))"),
    "phase_whole_asarray": ("((e ", "(k ", "((e (_ as-array k!0))" + EW),
    "phase_whole_bv": ("((e ", "(k ", "((e (store ((as const " + E5 + ") (_ bv0 5)) (_ bv0 32)"
                       " (_ bv3 5)))" + EW),
    "phase_whole_bv_bad": ("((e ", "(k ", "((e ((as const " + E5 + ") (_ bv0 5 junk)))" + EW),
    "phase_whole_bv_open":
    ("((e ", "(k ", "((e (let ((x (_ bv0 5 z))) ((as const " + E5 + ") x)))" + EW),
    "phase_whole_chain": ("((e ", "(k ", "((e (let ((a0 ((as const " + E5 + ") #b00000))) " +
                          "".join(f"(let ((a{k} (store a{k - 1} #x{k:08x} #b00001))) "
                                  for k in range(1, 3000)) + "a2999" + ")" * 3000 + ")" + EW),
    "phase_whole_compact": ("((e ", "(k ", "((e (store((as const(Array(_ BitVec 32)(_ BitVec 5)))"
                            "#b00000)#x00000000 #b00011))" + EW),
    "phase_whole_const_open":
    ("((e ", "(k ", "((e (let ((a ((as const " + E5 + " x #b00000) junk))) a))" + EW),
    "phase_whole_deep": ("((e ", "(k ", "((e " + "(let ((a " * 100000 + "((as const " + E5 +
                         ") #b00000)" + ")) a)" * 100000 + ")" + EW),
    "phase_whole_elem": ("((e ", "(k ", "((e ((as const " + E5 + ") #b0000))" + EW),
    "phase_whole_extra": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000 #b00001))" + EW),
    "phase_whole_extra_store": ("((e ", "(k ", "((e (store ((as const " + E5 + ") #b00000)"
                                " #x00000000 #b00011 #b00001))" + EW),
    "phase_whole_index":
    ("((e ", "(k ", "((e (store ((as const " + E5 + ") #b00000) #b0 #b00011))" + EW),
    "phase_whole_junk": ("((e ", "(k ", "((e junk)" + EW),
    "phase_whole_let": ("((e ", "(k ", "((e (let ((a ((as const " + E5 + ") #b00000)))"
                        " (store a #x00000000 #b00011)))" + EW),
    "phase_whole_let_dup": ("((e ", "(k ", "((e (let ((a ((as const " + E5 +
                            ") #b00000)) (a ((as const " + E5 + ") #b00000))) a))" + EW),
    "phase_whole_let_empty": ("((e ", "(k ", "((e (let () ((as const " + E5 + ") #b00000)))" + EW),
    "phase_whole_let_free": ("((e ", "(k ", "((e (let ((a junk)) a))" + EW),
    "phase_whole_let_lit": ("((e ", "(k ",
                            "((e (let ((#b00000 ((as const " + E5 + ") #b00000))) #b00000))" + EW),
    "phase_whole_let_nul": ("((e ", "(k ",
                            "((e (let ((a\0b ((as const " + E5 + ") #b00000))) a\0b))" + EW),
    "phase_whole_let_num": ("((e ", "(k ",
                            "((e (let ((0 ((as const " + E5 + ") #b00000))) 0))" + EW),
    "phase_whole_let_quoted": ("((e ", "(k ",
                               "((e (let ((|a| ((as const " + E5 + ") #b00000))) |a|))" + EW),
    "phase_whole_let_reserved": ("((e ", "(k ",
                                 "((e (let ((as ((as const " + E5 + ") #b00000))) as))" + EW),
    "phase_whole_let_seq": ("((e ", "(k ",
                            "((e (let ((a ((as const " + E5 + ") #b00000)) (b a)) b))" + EW),
    "phase_whole_let_sort": ("((e ", "(k ", "((e (let ((a #b00000)) a))" + EW),
    "phase_whole_let_spare": ("((e ", "(k ",
                              "((e (let ((b #b00000)) ((as const " + E5 + ") #b00000)))" + EW),
    "phase_whole_let_unused": ("((e ", "(k ",
                               "((e (let ((b junk)) ((as const " + E5 + ") #b00000)))" + EW),
    "phase_whole_lines": ("((e ", "(k ", "((e ((as const\n (Array (_ BitVec 32)\n (_ BitVec 5)))"
                          " #b00000))" + EW),
    "phase_whole_select": ("((e ", "(k ", "(((select e #x00000000) #b00000)" + EW),
    "phase_whole_shadow_bv":
    ("((e ", "(k ",
     "((e (let ((bv0 #b00000)) (store ((as const " + E5 + ") bv0) #x00000000 (_ bv0 5))))" + EW),
    "phase_whole_shadow_const":
    ("((e ", "(k ", "((e (let ((const #b00000)) ((as const " + E5 + ") const)))" + EW),
    "phase_whole_shadow_store": ("((e ", "(k ", "((e (let ((store ((as const " + E5 +
                                 ") #b00000))) (store store #x00000000 #b00011)))" + EW),
    "phase_whole_sort": ("((e ", "(k ", "((e ((as const (Array (_ BitVec 16) (_ BitVec 5)))"
                         " #b00000))" + EW),
    "phase_whole_store": ("((e ", "(k ", "((e (store ((as const " + E5 + ") #b00000) #x00000000"
                          " #b00011))" + EW),
    "phase_whole_store_let": ("((e ", "(k ", "((e (store (let ((a ((as const " + E5 +
                              ") #b00000))) a) #x00000000 #b00011))" + EW),
    "phase_whole_trail": ("((e ", "(k ", "((e ((as const " + E5 + ") #b00000) junk)" + EW),
}
# Modes acting on an unsat-assumptions reply, which lists __Va<N> literals
ASSUME_MODES = ("err_assume", "garbage_assume", "oor_assume", "stale_assume")
# Modes acting on an unsat-core reply, which lists __Vcons<N> names
CORE_MODES = ("core_junk", "err_core")
# Modes rewriting every line, so they never consume the index
STREAM_MODES = ("bin_literals", "bv_literals", "bv_spaced", "crlf", "csa_unsupported", "indent",
                "multiline", "success")
# Modes that change commands on their way to the solver
INPUT_MODES = ("csa_unsupported", "err_cell")
# Echoed in place of a command, to mark where in the replies its answer belongs
TAMPER_MARK = "vl_tamper"


def real_solver():
    """Return argv for the first SMT solver found in PATH"""
    for cmd in (["z3", "-in"], ["cvc5", "--incremental"], ["cvc4", "--lang=smt2",
                                                           "--incremental"]):
        if shutil.which(cmd[0]):
            return cmd
    sys.exit("randomize_solver_tamper.py: no SMT solver found")


proc = subprocess.Popen(real_solver(),
                        stdin=subprocess.PIPE if mode in INPUT_MODES else sys.stdin,
                        stdout=subprocess.PIPE,
                        text=True)

# err_cell: count is the push, pop and reset commands sent so far, pushed is
# whether the last of them was a push, and cell_after the scope the estimate
# ended in, once known
scopes = types.SimpleNamespace(count=0, pushed=False, cell_after=None)


def feed():
    """Pass the runtime's commands on, counting push, pop and reset for err_cell
    and replacing check-sat-assuming with a marker echo for csa_unsupported"""
    for cmd in sys.stdin:
        text = cmd.lstrip()
        if mode == "csa_unsupported" and text.startswith("(check-sat-assuming"):
            cmd = '(echo "' + TAMPER_MARK + '")\n'
        # The runtime reads each status before it sends the next push, pop or reset,
        # so a status is read while the count is still that of its check-sat
        if text.startswith(("(push", "(pop", "(reset)")):
            scopes.count += 1
            scopes.pushed = text.startswith("(push")
        if text.startswith("(reset)"):
            scopes.cell_after = None
        proc.stdin.write(cmd)
        proc.stdin.flush()
    proc.stdin.close()


if mode in INPUT_MODES:
    threading.Thread(target=feed, daemon=True).start()


def emit(text):
    """Write one reply line downstream, unbuffered"""
    sys.stdout.write(text + ("\r\n" if mode == "crlf" else "\n"))
    sys.stdout.flush()


def forward(text, at_start):
    """Pass a real reply through, applying the whole-stream rewrites"""
    # Other SMT-LIB 2.6 spellings of the same bit-vector values, select indices included
    if mode == "bin_literals":
        text = re.sub(r"#x([0-9a-fA-F]+)",
                      lambda m: "#b" + bin(int(m[1], 16))[2:].zfill(4 * len(m[1])), text)
    if mode == "bv_literals":
        text = re.sub(r"#x([0-9a-fA-F]+)", lambda m: f"(_ bv{int(m[1], 16)} {4 * len(m[1])})",
                      text)
        text = re.sub(r"#b([01]+)", lambda m: f"(_ bv{int(m[1], 2)} {len(m[1])})", text)
    if mode == "bv_spaced":
        text = re.sub(r"#x([0-9a-fA-F]+)", lambda m: f"( _\tbv{int(m[1], 16)}\n{4 * len(m[1])} )",
                      text)
    # Solvers echo success per command, so never inside a wrapped S-expression
    if mode == "success" and at_start:
        emit("success")
    if mode == "multiline" and text.startswith("(") and not text.startswith("(error"):
        for tok in text.split():
            emit(tok)
    elif mode == "indent":
        emit(" \t" + text)
    else:
        emit(text)


def scan_depth(text, left, in_string):
    """Paren depth of text, ignoring parens inside SMT string literals"""
    for char in text:
        if in_string:
            in_string = char != '"'
        elif char == '"':
            in_string = True
        elif char == "(":
            left += 1
        elif char == ")":
            left -= 1
    return left, in_string


def read_full(first):
    """Return the complete S-expression reply that starts at first"""
    chunks = [first]
    left, in_string = scan_depth(first, 0, False)
    while left > 0:
        cont = proc.stdout.readline()
        if not cont:
            break
        chunks.append(cont.rstrip("\n"))
        left, in_string = scan_depth(cont, left, in_string)
    return chunks


def mute():
    """Close the reply pipe but keep running until the runtime gives up on this solver"""
    os.close(1)
    proc.kill()
    proc.wait()
    parent = os.getppid()
    while os.getppid() == parent:
        time.sleep(0.05)
    sys.exit(0)


def swallow(first):
    """Drop the rest of a real S-expression reply that was replaced"""
    read_full(first)


replies = 0
seen_unsat = False
done = bool(once) and os.path.exists(once)
marker_next = False  # err_marker: the next status follows an error holding the marker
sat_scope = None  # err_cell: the scope of the last sat
depth = 0  # Paren depth of the reply being forwarded, so wrapped ones stay intact
inside = False  # Inside an SMT string literal, where parens do not nest

for line in proc.stdout:
    line = line.rstrip("\n")
    if mode == "csa_unsupported" and line in (TAMPER_MARK, '"' + TAMPER_MARK + '"'):
        emit("unsupported")
        continue
    # z3 prints an echoed string bare; SMT-LIB 2.6 section 4.2.9 keeps its quotes
    if mode in ("err_cell", "err_extra") and line == "vl_resync":
        line = '"vl_resync"'
    at_reply_start = depth == 0
    depth, inside = scan_depth(line, depth, inside)
    is_status = line in ("sat", "unsat", "unknown")
    if mode in STATUS_MODES:
        counted = is_status
    elif mode in REPLY_MODES:
        # Only a first line opens a reply; a wrapped continuation is not a new one
        counted = at_reply_start and line.startswith("(")
    elif mode in SELECT_MODES:
        counted = at_reply_start and line.startswith("(((select")
    elif mode in CELL_MODES:
        counted = (is_status and scopes.pushed and scopes.cell_after is not None
                   and scopes.count > scopes.cell_after)
        if is_status and scopes.pushed and scopes.cell_after is None:
            if line == "unsat" and sat_scope == scopes.count:
                scopes.cell_after = scopes.count
            sat_scope = scopes.count if line == "sat" else None
    elif mode in RECHECK_MODES:
        counted = is_status and seen_unsat
    elif mode in PHASE_MODES:
        counted = at_reply_start and line.startswith("((x")
    elif mode in PHASE_VALUE_MODES:
        counted = at_reply_start and line.startswith(PHASE_VALUE_MODES[mode][0])
    elif mode in ASSUME_MODES:
        counted = at_reply_start and re.match(r"\(__Va\d", line) is not None
    elif mode in CORE_MODES:
        counted = at_reply_start and line.startswith("(__Vcons")
    else:
        counted = at_reply_start and line.startswith("((")
    if line == "unsat":
        seen_unsat = True
    if counted:
        replies += 1
    if marker_next and is_status:
        marker_next = False
        emit('(error "injected command rejected, then')
        emit("vl_resync")
        emit('in its text")')
    acting = counted and replies >= at and not done and mode not in STREAM_MODES
    if not acting:
        forward(line, at_reply_start)
        continue
    if once:
        with open(once, "w", encoding="utf-8"):
            pass

    done = True

    if mode == "bad_base":
        emit("((a #z01) (b #x12))")
        swallow(line)
        continue
    if mode == "bad_digits":
        emit("((a #x0b) (b #xgg))")
        swallow(line)
        continue
    if mode == "bad_index":
        emit("(((select q #xgg) #x15) ((select q #x00000001) #x15)"
             " ((select q #x00000002) #x15))")
        swallow(line)
        continue
    # A well-formed reply whose second value is unusable: the first must not
    # reach the variable either
    if mode == "bad_value":
        emit("((a #x0b) (b bogus))")
        swallow(line)
        continue
    if mode == "bare_hash":
        emit("((a #x0b) (b #))")
        swallow(line)
        continue
    if mode == "binary":
        emit("((a #b00001011) (b #b00010010))")
        swallow(line)
        continue
    if mode == "frozen_value":
        emit("((f #x0b) (g #x!))")
        swallow(line)
        continue
    # Indexed literals the parser must reject: the first, valid one must not be written either
    bad_bv = {
        "bv_digits": "(_ bvx12 8)",
        "bv_long": "(_ bv123456789 8)",
        "bv_overflow": "(_ bv256 8)",
        "bv_sort": "(_ bv0 2147483647)"
    }
    if mode in bad_bv:
        emit("((a (_ bv11 8)) (b " + bad_bv[mode] + "))")
        swallow(line)
        continue
    if mode == "core_junk":
        emit("junk((__Vcons0))")
        proc.kill()
        proc.wait()
        sys.exit(0)
    # The base model comes first, so a later one belongs to a diversity round
    if mode == "diversity_model":
        emit("(((select q #x00000000) bogus))")
        swallow(line)
        continue
    if mode == "dup_model":
        emit("((a #x0b) (a #x0c) (b #x05))")
        swallow(line)
        continue
    if mode == "err_assume":
        emit('(error "injected assumptions error")')
        swallow(line)
        continue
    if mode == "err_core":
        emit('(error "injected core error")')
        swallow(line)
        continue
    if mode in ("err_cell", "err_extra"):
        emit('(error "injected earlier command rejected")')
        forward(line, at_reply_start)
        continue
    if mode == "err_marker":
        emit('(error "injected command rejected")')
        marker_next = True
        continue
    if mode == "err_multiline":
        emit('(error "injected')
        emit('multiline error")')
        continue
    if mode == "err_once":
        emit('(error "injected command rejected")')
        continue
    if mode == "err_mute":
        emit('(error "injected command rejected")')
        mute()
    # The first phase value reply always precedes the final phased model
    if mode == "err_phase":
        emit('(error "injected phase value error")')
        swallow(line)
        continue
    if mode == "err_reply":
        emit('(error "injected reply error")')
        swallow(line)
        continue
    if mode == "err_trunc":
        emit('(error "unterminated')
        proc.kill()
        proc.wait()
        sys.exit(0)
    if mode == "err_unbal":
        emit('(error "unbalanced"))')
        continue
    if mode == "err_unbal_cont":
        emit('(error "unbalanced"')
        emit('))')
        continue
    if mode == "garbage_assume":
        emit("junk")
        swallow(line)
        continue
    # garbage_at repeats, so it re-arms instead of latching
    if mode == "garbage_at":
        replies = 0
        done = False
        emit("junk")
        continue
    if mode == "garbage_model":
        emit("((a #x0b) junk)")
        swallow(line)
        continue
    if mode == "garbage_status":
        emit("flurble")
        continue
    if mode == "high_digit":
        emit("((a #x0b) (b #b2))")
        swallow(line)
        continue
    if mode == "low_digit":
        emit("((a #x0b) (b #x!))")
        swallow(line)
        continue
    if mode == "model_trunc":
        emit("((a #x0b)")
        proc.kill()
        proc.wait()
        sys.exit(0)
    if mode == "no_digits":
        emit("((a #x0b) (b #x))")
        swallow(line)
        continue
    if mode == "octal":
        emit("((a #o13) (b #o12))")
        swallow(line)
        continue
    if mode == "oor_assume":
        emit("(__Va99999999999999)")
        swallow(line)
        continue
    # Only the final phase queries every variable, so only that reply names y
    if mode == "phase_model":
        replies = 0  # Re-arm until the final phase is seen
        done = False
        parts = read_full(line)
        if "(y " in " ".join(parts):
            emit('(error "injected phased model error")')
        else:
            for part in parts:
                forward(part, part is parts[0])
        continue
    if mode in PHASE_VALUE_MODES:
        parts = read_full(line)
        if PHASE_VALUE_MODES[mode][1] in " ".join(parts):
            # A final model is not a phase value reply; re-arm for the next one
            replies -= 1
            done = False
            for part in parts:
                forward(part, part is parts[0])
        else:
            emit(PHASE_VALUE_MODES[mode][2])
        continue
    if mode == "phase_trunc":
        emit("((x")
        proc.kill()
        proc.wait()
        sys.exit(0)
    # Malformed selects, in a reply that answers each other element. The duplicate takes the
    # place of q[1], so the reply still has as many answers as requested.
    q_rest = (" ((select q #x00000002) #x15)"
              " ((select wide #x0000000123456789abcdef01) #x4d) (z #x00))")
    bad_select = {
        "select_digit": "((select q #x00000000 0) #x15) ((select q #x00000001) #x15)",
        "select_arity":
        "((select (select q #x00000000) #x00000000) #x15) ((select q #x00000001) #x15)",
        "select_carry": "((select q (_ bv4294967296 32)) #x15) ((select q #x00000001) #x15)",
        "select_dup": "((select q #x00000000) #x15) ((select q #b" + "0" * 32 + ") #x16)",
        "select_empty": "((select e #x00000000) #x15) ((select q #x00000001) #x15)",
        "select_lead": "((select q 0 #x00000000) #x15) ((select q #x00000001) #x15)",
        "select_narrow": "((select q #b0) #x15) ((select q #x00000001) #x15)",
        "select_octal": "((select q #o00000000000) #x15) ((select q #x00000001) #x15)",
        "select_wide": "((select q #x100000000) #x15) ((select q #x00000001) #x15)",
        "select_extra": "((select q #x00000000 #x00000001) #x15) ((select q #x00000001) #x15)",
        "select_prefix": "((selectx q #x00000000) #x15) ((select q #x00000001) #x15)",
        "select_scalar": "((select z #x00000000) #x15) ((select q #x00000001) #x15)",
        "select_unknown": "((select q #x00000003) #x15) ((select q #x00000001) #x15)",
        "select_whole": "(q #x15) ((select q #x00000001) #x15)"
    }
    if mode in bad_select:
        emit("(" + bad_select[mode] + q_rest)
        swallow(line)
        continue
    if mode == "short_model":
        emit("((a #x0b))")
        swallow(line)
        continue
    # Naming the already dropped __Va0 leaves the real conflict in place, so every round
    # stays unsat up to the round limit; it keeps acting instead of latching
    if mode == "stale_assume":
        done = False
        emit("(__Va0)")
        swallow(line)
        continue
    if mode == "unknown_once":
        emit("unknown")
        continue
    if mode == "unknown_twice":
        emit("unknown")
        done = replies >= at + 1
        continue
    if mode == "unknown_var":
        emit("((zzz #x01) (b #x12))")
        swallow(line)
        continue
    # Every re-solve answers the same way, so this re-arms instead of latching
    if mode == "unsat_recheck":
        replies = 0
        seen_unsat = False
        done = False
        emit("sat")
        continue
    if mode == "unsupported_once":
        emit("unsupported")
        continue
    if mode == "value_digit":
        emit("((a #x0b 0) (b #x12))")
        swallow(line)
        continue
    if mode == "value_lead":
        emit("((a 0 #x0b) (b #x12))")
        swallow(line)
        continue
    if mode == "value_narrow":
        emit("((a #b0) (b #x12))")
        swallow(line)
        continue
    if mode == "value_wide":
        emit("((a #x00b) (b #x12))")
        swallow(line)
        continue
    if mode == "upper_hex":
        emit("((a #xAB) (b #x12))")
        swallow(line)
        continue
    forward(line, at_reply_start)

    if mode in ("die_at", "die_status_at"):
        proc.kill()
        proc.wait()
        sys.exit(0)
    if mode == "mute_at":
        mute()
