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

test.compile(verilator_flags2=['--binary'])

test.execute()

# Each forward class declaration in a header is guarded, so a translation unit including
# many headers declares the class once
n_decls = 0
for filename in test.glob_some(test.obj_dir + "/*.h"):
    with open(filename, 'r', encoding="utf8") as fh:
        lines = fh.read().splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'^class (\w+);$', line)
        if not m:
            continue
        n_decls += 1
        if lines[i - 1] != "#define VL_FWD_" + m.group(1):
            test.error(filename + ": Unguarded forward declaration: " + line)

if n_decls < 10:
    test.error("Expected forward declarations of Syms, classes and cells, got " + str(n_decls))
test.file_grep(test.obj_dir + "/" + test.vm_prefix + "___024unit__03A__03AClsB__Vclpkg.h",
               r'#ifndef VL_FWD_' + test.vm_prefix + r'___024unit__03A__03ACommon\n')

test.passes()
