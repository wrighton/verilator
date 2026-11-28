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

test.compile(verilator_flags2=["--binary --assert"])

test.execute(all_run_flags=["+verilator+error+limit+100"])

# The concurrent and observed deferred assertion actions of a tick all run in the Reactive
# region, in an unspecified order (IEEE 1800-2023 4.7, 16.4.1, 16.14.1), so each run of their
# reports is compared sorted
reactive = re.compile(r'^\[\d+\] %Error: t_assert_pass_only\.v:(26|27|28|29|44): ')
lines = []
run = []
for line in test.file_contents(test.run_log_filename).splitlines(keepends=True):
    if reactive.match(line):
        run.append(line)
        continue
    lines += sorted(run) + [line]
    run = []
lines += sorted(run)
sorted_filename = test.obj_dir + "/sorted.log"
with open(sorted_filename, 'w', encoding='latin-1') as fh:
    fh.writelines(lines)
test.files_identical(sorted_filename, test.golden_filename, is_logfile=True)

test.passes()
