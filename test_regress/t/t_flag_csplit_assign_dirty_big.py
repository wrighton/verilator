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

# The copy of the input made to detect its changes, over the default limit, is split, and copies
# bits above its width as without the split, so the input does not keep appearing changed. The
# input is set with such bits, which the checks of VL_DEBUG would report.
test.compile(make_top_shell=False,
             make_main=False,
             verilator_flags2=['--exe', test.pli_filename, '--stats', '-CFLAGS', '-UVL_DEBUG'])

test.execute()

test.file_grep(test.stats, r'Outline, wide assignments split\s+([1-9]\d*)')

test.passes()
