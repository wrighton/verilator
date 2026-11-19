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

secret_prefix = "secret"
secret_dir = test.obj_dir + "/" + secret_prefix
test.mkdir_ok(secret_dir)

# Build the library from the module with escaped port names
test.run(logfile=secret_dir + "/vlt_compile.log",
         cmd=["perl", os.environ["VERILATOR_ROOT"] + "/bin/verilator",
              "--no-timing",
              "--prefix", test.vm_prefix + "_secret",
              "-cc",
              "-Mdir", secret_dir,
              "--protect-lib", secret_prefix,
              "--protect-key", "secret-key",
              "+define+SECRET_SOURCE",
              test.top_filename],
         verilator_run=True)  # yapf:disable

test.run(logfile=secret_dir + "/secret_gcc.log",
         cmd=[os.environ["MAKE"], "-C", secret_dir, "-f", test.vm_prefix + "_secret.mk"])

# The generated wrapper must be legal for the design using the library
test.compile(verilator_flags2=['--no-timing',
                               "-LDFLAGS", secret_prefix + "/libsecret.a",
                               secret_dir + "/secret.sv"])  # yapf:disable

test.execute()

test.passes()
