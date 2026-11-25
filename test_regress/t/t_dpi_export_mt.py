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
test.enable_tsan()

other_prefix = "V" + test.name + "_other"
other_dir = os.path.abspath(test.obj_dir + "/other")
test.mkdir_ok(other_dir)

test.run(logfile=other_dir + "/vlt_compile.log",
         cmd=[os.environ["VERILATOR_ROOT"] + "/bin/verilator",
              "--cc",
              "--prefix", other_prefix,
              "-Mdir", other_dir,
              "t/" + test.name + "_other.v"],
         verilator_run=True)  # yapf:disable

test.run(logfile=other_dir + "/vlt_gcc.log",
         cmd=[os.environ["MAKE"], "-C", other_dir, "-f", other_prefix + ".mk"])

test.compile(make_main=False,
             verilator_flags2=["--exe", test.pli_filename,
                               "-CFLAGS", "-I" + other_dir,
                               other_dir + "/" + other_prefix + "__ALL.a"])  # yapf:disable

test.execute()

test.passes()
