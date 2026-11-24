// DESCRIPTION: Verilator: DPI import for t_hier_block_comb_outputs
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "svdpi.h"

extern "C" void blk_set_y(svBit x);
extern "C" void blk_call_set_y(svBit x) { blk_set_y(x); }
