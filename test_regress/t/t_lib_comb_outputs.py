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
test.top_filename = "t/t_hier_block_comb_outputs.v"

# The blocks of t_hier_block_comb_outputs as libraries made with --lib-create
libs = []
# Also dumping the tree, for the dump of the outputs the wrapper takes from the clock update alone
for module, lib, extra in (("blk", "blklib", [
        test.t_dir + "/t_hier_block_comb_outputs.cpp", "--dumpi-tree 3", "--dumpi-tree-json 3"
]), ("blk_t", "blktlib", []), ("blk_q", "blkqlib", []), ("blk_c", "blkclib", []), ("blk_n",
                                                                                   "blknlib", [])):
    lib_dir = test.obj_dir + "/" + lib
    test.mkdir_ok(lib_dir)
    test.run(
        logfile=lib_dir + "/vlt_compile.log",
        cmd=[
            os.environ["VERILATOR_ROOT"] + "/bin/verilator", "--cc", "--timing", "--top-module",
            module, "--prefix", "V" + lib, "--lib-create", lib, "-Mdir", lib_dir, test.top_filename
        ] + extra,
        verilator_run=True)
    test.run(logfile=lib_dir + "/vlt_gcc.log",
             cmd=[os.environ["MAKE"], "-C", lib_dir, "-f", "V" + lib + ".mk", "lib" + lib + ".a"])
    libs += [lib_dir + "/" + lib + ".sv", "-LDFLAGS", lib + "/lib" + lib + ".a"]

test.compile(verilator_flags2=[
    "--binary", "--timing", "--top-module", "t", "+define+BLK=blklib", "+define+BLK_T=blktlib",
    "+define+BLK_Q=blkqlib", "+define+BLK_C=blkclib", "+define+BLK_N=blknlib"
] + libs)

test.execute()

test.passes()
