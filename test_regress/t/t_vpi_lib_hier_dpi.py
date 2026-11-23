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

# A library with VPI created through its C interface, as by its wrapper in another simulator
test.vm_prefix = "Vlib_sub"
# Single threaded, as the library is evaluated within the threads of the model using it
test.compile(make_main=False,
             threads=1,
             verilator_make_gmake=False,
             verilator_flags2=["--vpi", "--lib-create", "sub", "--top-module", "sub"])
test.run(logfile=test.obj_dir + "/" + test.vm_prefix + "_make.log",
         cmd=[os.environ["MAKE"], "-C", test.obj_dir, "-f", test.vm_prefix + ".mk", "libsub.a"])

test.vm_prefix = "Vt"
test.compile(make_main=False,
             make_top_shell=False,
             verilator_flags2=[
                 "--exe", "--vpi", test.pli_filename, "+define+USE_LIB", "--top-module", "t",
                 "libsub.a"
             ])
test.execute()

test.passes()
