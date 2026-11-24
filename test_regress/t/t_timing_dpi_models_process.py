#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import vltest_bootstrap

test.scenarios("vlt")

test.compile(make_main=False,
             vm_prefix="Vb",
             verilator_make_gmake=False,
             verilator_flags2=["--timing", "--top-module", "b"])

# Vb links with Va and shares VL_DEBUG-dependent runtime layout, so build it with the same flags
# as Va (VL_DEBUG, model optimization)
test.run(cmd=[os.environ["MAKE"], "-C", test.obj_dir,
              "-f", os.getcwd() + "/Makefile_obj",
              "VM_PREFIX=Vb",
              "TEST_OBJ_DIR=" + test.obj_dir,
              "CPPFLAGS_DRIVER=-D" + test.name.upper(),
              ("CPPFLAGS_DRIVER2=-DTEST_VERBOSE=1" if test.verbose else ""),
              ("" if test.benchmark else "OPT_FAST=-O0"),
              "Vb__ALL.a"])  # yapf:disable

test.vm_prefix = "Va"
test.compile(make_main=False,
             v_flags2=[os.path.abspath(test.obj_dir + "/Vb__ALL.a")],
             verilator_flags2=["--timing", "--top-module", "a", "--exe", test.pli_filename])
test.execute(check_finished=True)

test.passes()
