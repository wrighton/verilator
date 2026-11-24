// DESCRIPTION: Verilator: DPI import for t_hier_block_feedback
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated_vpi.h"

#include VM_PREFIX_INCLUDE_DPI

#include <cstdio>

void dpii_force(const char* name, int value, svBit do_release) {
    vpiHandle const handlep = vpi_handle_by_name(const_cast<PLI_BYTE8*>(name), nullptr);
    if (!handlep) {
        printf("%%Error: cannot find %s\n", name);
        return;
    }
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = value;
    vpi_put_value(handlep, &val, nullptr, do_release ? vpiReleaseFlag : vpiForceFlag);
    vpi_release_handle(handlep);
}
