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

test.lint(v_flags=["--dumpi-tree 9", "--dumpi-tree-json 9", "--dumpi-V3EmitV 9", "--debug-emitv"])


def emitted(stage, suffix=".v"):
    return test.glob_one(test.obj_dir + "/" + test.vm_prefix + "_*_" + stage + ".tree" + suffix)


# Before linking, the disable names its target as written
test.file_grep(emitted("linkparse"), r'disable \\blk-a ;')
test.file_grep(emitted("linkparse"), r'disable \\fork ;')
test.file_grep(emitted("linkparse"), r'disable \\tsk-c ;')
# Once linked, it names the target as written, so that it is found the same way again
test.file_grep(emitted("linkresolve"), r'disable \\blk-a ;')
test.file_grep(emitted("linkresolve"), r'disable \\fork ;')
test.file_grep(emitted("linkresolve"), r'disable \\tsk-c ;')
test.file_grep(emitted("linkresolve"), r'disable \\outer-a \.\\blk-e ;')
test.file_grep(emitted("linkresolve"), r'disable \\u-x \.\\outer-b \.\\blk-d ;')
test.file_grep(emitted("linkresolve"), r'disable \\worker-s ;')
test.file_grep(emitted("linkresolve"), r'disable TOP\.\\outer-b ;')
# The path kept is also dumped
test.file_grep(emitted("linkresolve", ".json"), r'"targetPath":"TOP\.outer__02db"')

test.passes()
