#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2024 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import json
import vltest_bootstrap

test.scenarios('dist')


def have_clang_check():
    cmd = 'python3 -c "from clang.cindex import Index; index = Index.create(); print(\\"Clang imported\\")";'
    if test.verbose:
        print("\t" + cmd)
    nout = test.run_capture(cmd, check=False)
    if not nout or not re.search(r'Clang imported', nout):
        return False
    return True


if 'VERILATOR_TEST_NO_ATTRIBUTES' in os.environ:
    test.skip("Skipping due to VERILATOR_TEST_NO_ATTRIBUTES")
if not os.path.exists(test.root + "/.git"):
    test.skip("Not in a git repository")
if not have_clang_check():
    test.skip("No libclang installed")

aroot = os.path.abspath(test.root)
ccjson_file = test.obj_dir + "/compile_commands.json"

aroot_dir = os.path.abspath(test.root)
srcs_dir = os.path.abspath("./t/t_dist_attributes")
common_args = [
    "clang++", "-std=c++14", "-I" + aroot_dir + "/include", "-I" + aroot_dir + "/src", "-c"
]

ccjson = [
    {
        "directory": srcs_dir,
        "file": srcs_dir + "/mt_enabled.cpp",
        "output": srcs_dir + "/mt_enabled.o",
        "arguments":
        [*common_args, "-o", srcs_dir + "/mt_enabled.o", srcs_dir + "/mt_enabled.cpp"]
    },
    {
        "directory": srcs_dir,
        "file": srcs_dir + "/mt_disabled.cpp",
        "output": srcs_dir + "/mt_disabled.o",
        "arguments":
        [*common_args, "-o", srcs_dir + "/mt_disabled.o", srcs_dir + "/mt_disabled.cpp"]
    },
]
ccjson_str = json.dumps(ccjson)

srcfiles = []
for entry in ccjson:
    srcfiles.append(entry["file"])
srcfiles_str = ' '.join(srcfiles)

test.write_wholefile(ccjson_file, ccjson_str)

test.run(
    logfile=test.run_log_filename,
    tee=True,
    # With `--verilator-root` set to the current directory
    # (i.e. `test_regress`) the script will skip annotation issues in
    # headers from the `../include` directory.
    cmd=[
        "python3", aroot + "/nodist/clang_check_attributes", "--verilator-root=.",
        "--compile-commands-dir=" + test.obj_dir, "--jobs=1", srcfiles_str
    ])

test.files_identical(test.run_log_filename, test.golden_filename)

# Callers of runtime helpers: with the Verilator root as the root, the script also checks the
# annotations of the functions they call in ../include
runtime_dir = test.obj_dir + "/runtime"
runtime_log = runtime_dir + "/runtime.log"
os.makedirs(runtime_dir, exist_ok=True)
runtime_ccjson = [{
    **ccjson[0], "arguments": [
        *common_args, "-DT_DIST_ATTRIBUTES_RUNTIME", "-o", srcs_dir + "/mt_enabled.o",
        srcs_dir + "/mt_enabled.cpp"
    ]
}]
test.write_wholefile(runtime_dir + "/compile_commands.json", json.dumps(runtime_ccjson))

test.run(logfile=runtime_log,
         cmd=[
             "python3", aroot + "/nodist/clang_check_attributes", "--verilator-root=" + aroot,
             "--compile-commands-dir=" + runtime_dir, "--jobs=1", srcs_dir + "/mt_enabled.cpp"
         ])

test.file_grep(runtime_log,
               r'"runtime_append_pure_caller\([^"]*\)" is pure but calls non-pure function')
test.file_grep_not(runtime_log, r'"runtime_append_mt_safe_caller')

test.passes()
