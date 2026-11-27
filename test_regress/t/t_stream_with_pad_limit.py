#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import re
import shutil

import vltest_bootstrap

test.scenarios('simulator')

test.compile()

# A padded range of 2**32 items would need gigabytes; bound the run to 1 GiB where possible, not
# with a sanitizer, whose shadow memory needs a large address space
sanitized = (test.tsan or test.have_dev_asan
             or re.search(r'--runtime-debug', ' '.join(test.driver_verilator_flags)))
test.execute(
    run_env='prlimit --as=1073741824 --' if shutil.which('prlimit') and not sanitized else '')

test.passes()
