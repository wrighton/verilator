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

# Libraries whose names have internal markers, and ports named like functions of their wrappers
test.compile(verilator_flags2=["--top-module", "t", "--lib-create", "lib__DOT__name"],
             verilator_make_gcc=False,
             verilator_make_gmake=False,
             make_main=False,
             make_top_shell=False)

marker_dir = test.obj_dir + "/marker"
test.mkdir_ok(marker_dir)
test.run(logfile=marker_dir + "/vlt_compile.log",
         cmd=[
             os.environ["VERILATOR_ROOT"] + "/bin/verilator", "--cc", "--top-module", "marker",
             "--prefix", "Vmarker", "--lib-create", "left__PVT__right", "-Mdir", marker_dir,
             test.top_filename
         ],
         verilator_run=True)

test.lint(v_flags2=[
    "+define+CONSUMER", "--top-module", "consumer", test.obj_dir + "/lib__DOT__name.sv",
    marker_dir + "/left__PVT__right.sv"
],
          logfile=test.obj_dir + "/consumer_lint.log")

test.passes()
