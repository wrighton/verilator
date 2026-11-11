#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('simulator')

test.compile(verilator_flags2=['--binary'])

test.execute()

# Only modules with a class referring to their instance are copied per instance
test.file_grep(test.obj_dir + "/" + test.vm_prefix + "_classes.mk", r'sub___Vinst1')
test.file_grep(test.obj_dir + "/" + test.vm_prefix + "_classes.mk", r'counter___Vinst1')
test.file_grep_not(test.obj_dir + "/" + test.vm_prefix + "_classes.mk", r'shared___Vinst')

test.passes()
