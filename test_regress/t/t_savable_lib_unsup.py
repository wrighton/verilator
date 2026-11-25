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
test.top_filename = "t/t_lib_prot.v"

secret_prefix = "secret"
secret_dir = test.obj_dir + "/" + secret_prefix
test.mkdir_ok(secret_dir)

test.run(logfile=secret_dir + "/vlt_compile.log",
         cmd=["perl", os.environ["VERILATOR_ROOT"] + "/bin/verilator",
              "--no-timing",
              "--prefix", "Vt_lib_prot_secret",
              "-cc",
              "-Mdir", secret_dir,
              "--lib-create", secret_prefix,
              "t/t_lib_prot_secret.v"],
         verilator_run=True)  # yapf:disable

test.lint(verilator_flags2=["--no-timing --savable", secret_dir + "/secret.sv"],
          fails=True,
          expect_filename=test.golden_filename)

test.passes()
