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

top_prefix = test.vm_prefix

test.vm_prefix = "Vlib_lib"
# Single threaded, as the library is evaluated within the threads of the model using it
test.compile(make_main=False,
             threads=1,
             verilator_make_gmake=False,
             verilator_flags2=["--lib-create", "lib", "--top-module", "lib"])
test.run(logfile=test.obj_dir + "/" + test.vm_prefix + "_make.log",
         cmd=[os.environ["MAKE"], "-C", test.obj_dir, "-f", test.vm_prefix + ".mk", "liblib.a"])

test.vm_prefix = top_prefix
test.compile(make_main=False,
             verilator_flags2=[
                 "--exe", test.pli_filename, "+define+USE_LIB", test.obj_dir + "/lib.sv",
                 "liblib.a"
             ])

test.execute()

# Order of lines is unspecified, so don't use a golden file
test.file_grep(test.run_log_filename, r"top: TOP\.q own")
test.file_grep(test.run_log_filename, r"lib: TOP\.t\.u_lib\.q own")

test.passes()
