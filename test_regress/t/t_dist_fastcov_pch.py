#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

# The coverage collector omits the empty notes file of a header-only precompile,
# which gcov reports without a working directory when it is first in a run, and
# keeps every other input as before

import json
import os
import shutil
import sys

import vltest_bootstrap

test.scenarios('dist')

if shutil.which('gcov') is None or shutil.which('g++') is None:
    test.skip("No g++/gcov")

odir = os.path.abspath(test.obj_dir)
root = os.path.abspath(test.root)
fastcov = [
    sys.executable, root + "/nodist/fastcov.py", "-j", "1", "--gcov", root + "/nodist/gcov_batch",
    "--lcov", "--process-gcno", "--branch-coverage"
]
test.write_wholefile(
    odir + "/Vt__pch.h",
    "#ifndef VT_PCH_H\n#define VT_PCH_H\ninline int f(int x) { return x ? 1 : 2; }\n#endif\n")
test.write_wholefile(odir + "/t.cpp", "int main(int argc, char**) { return f(argc) - 1; }\n")
# A header precompile with coverage writes an empty notes file
test.run(
    cmd=["cd " + odir + " && g++ --coverage -c -x c++-header Vt__pch.h -o Vt__pch.h.fast.gch"])
test.run(cmd=["cd " + odir + " && g++ --coverage -include Vt__pch.h.fast -c t.cpp -o t.o"])
if os.path.getsize(odir + "/Vt__pch.h.fast.gcno") != 0:
    test.skip("Compiler writes non-empty header precompile notes")

# Whether this gcov omits the working directory for an empty notes file first in its run.
# The probe must yield exactly one gcov JSON record for that file with no source files;
# anything else is an error rather than a choice of expectation.
test.run(logfile=odir + "/probe.log",
         cmd=[
             "cd " + odir + " && gcov --json-format --stdout " + odir +
             "/Vt__pch.h.fast.gcno > probe.json 2>/dev/null; echo \"probe-status=$?\""
         ])
probe_records = []
for line in test.file_contents(odir + "/probe.json").splitlines():
    if line.strip():
        try:
            probe_records.append(json.loads(line))
        except json.JSONDecodeError:
            test.error("gcov probe output is not JSON: " + line[:80])
if (len(probe_records) != 1 or not isinstance(probe_records[0], dict)
        or "format_version" not in probe_records[0] or probe_records[0].get("files") != []
        or not probe_records[0].get("data_file", "").endswith("Vt__pch.h.fast.gcno")):
    test.error("gcov probe did not yield one empty-files JSON record for the notes file")
missing_cwd_first = "current_working_directory" not in probe_records[0]

# Omitted when first in a run
test.run(logfile=odir + "/pch.log",
         cmd=[
             "cd " + odir + " && GCOV=gcov " + " ".join(fastcov) + " -f " + odir +
             "/Vt__pch.h.fast.gcno " + odir + "/t.gcno --output " + odir + "/pch.info"
         ])
test.file_grep(odir + "/pch.log", r"Omitted 1 empty header precompile notes files")
test.file_grep_not(odir + "/pch.log", r"Missing 'current_working_directory'")
test.file_grep(odir + "/pch.info", r"SF:.*/t\.cpp")

# An empty notes file that is not a header precompile output is still an error
test.write_wholefile(odir + "/u.gcno", "")
test.run(logfile=odir + "/empty.log",
         fails='any' if missing_cwd_first else False,
         cmd=[
             "cd " + odir + " && GCOV=gcov " + " ".join(fastcov) + " -f " + odir + "/u.gcno " +
             odir + "/t.gcno --output " + odir + "/empty.info"
         ])
test.file_grep_not(odir + "/empty.log", r"Omitted \d+ empty header precompile notes")
if missing_cwd_first:
    test.file_grep(odir + "/empty.log", r"Missing 'current_working_directory'")

# Without its header, the header precompile notes file is processed as before
os.rename(odir + "/Vt__pch.h", odir + "/Vt__pch.h.moved")
test.run(logfile=odir + "/nohdr.log",
         fails='any' if missing_cwd_first else False,
         cmd=[
             "cd " + odir + " && GCOV=gcov " + " ".join(fastcov) + " -f " + odir +
             "/Vt__pch.h.fast.gcno " + odir + "/t.gcno --output " + odir + "/nohdr.info"
         ])
test.file_grep_not(odir + "/nohdr.log", r"Omitted \d+ empty header precompile notes")
if missing_cwd_first:
    test.file_grep(odir + "/nohdr.log", r"Missing 'current_working_directory'")

test.passes()
