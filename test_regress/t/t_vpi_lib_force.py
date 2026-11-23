#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios('vlt_all')

test.vm_prefix = "Vlib_sub"
test.compile(make_main=False,
             threads=1,
             verilator_make_gmake=False,
             verilator_flags2=["--vpi", "--lib-create", "sub", "--top-module", "sub"])
test.run(logfile=test.obj_dir + "/" + test.vm_prefix + "_make.log",
         cmd=[os.environ["MAKE"], "-C", test.obj_dir, "-f", test.vm_prefix + ".mk", "libsub.a"])

# Three builds: flat, --hierarchical, and manual --lib-create, all behave the same
builds = (
    ("Vnonh", []),
    ("Vhier", ["--hierarchical"]),
    ("Vlibs", ["+define+USE_LIB", test.obj_dir + "/sub.sv", "libsub.a"]),
)
# With threads, evaluate in parallel whatever may be
thread_flags = ["-CFLAGS", "-DVL_THREADS_SERIAL_COST=0"] if test.vltmt else []
for prefix, extra_flags in builds:
    test.vm_prefix = prefix
    # Each model needs its own main, as they share the object directory
    main_filename = test.obj_dir + "/" + prefix + "__main.cpp"
    test.write_wholefile(main_filename, ("#define T_FLAT 1\n" if prefix == "Vnonh" else "") +
                         "#include \"" + os.path.abspath(test.pli_filename) + "\"\n")
    test.compile(make_main=False,
                 make_top_shell=False,
                 verilator_flags2=["--exe", "--vpi", main_filename] + extra_flags + thread_flags)
    test.execute(executable=test.obj_dir + "/" + prefix,
                 logfile=test.obj_dir + "/" + prefix + "__sim.log",
                 check_finished=True)

test.passes()
