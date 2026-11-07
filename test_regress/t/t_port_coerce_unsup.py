#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('linter')

test.lint(fails=test.vlt_all, expect_filename=test.golden_filename)

if test.vlt_all:
    test.lint(fails=True,
              verilator_flags2=['+define+PERMISSION_BAD'],
              expect_filename=test.golden_filename.replace('.out', '_permission.out'))
    test.lint(fails=True,
              verilator_flags2=['+define+ASSIGNIN_CHECK'],
              expect_filename=test.golden_filename.replace('.out', '_assignin.out'))

test.passes()
