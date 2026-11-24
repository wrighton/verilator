// DESCRIPTION: Verilator: DPI import for t_vpi_lib_force_timing
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated_vpi.h"

#include VM_PREFIX_INCLUDE_DPI

#include <cstdio>

void dpii_force(int value) {
    vpiHandle const ip = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.u.i"), nullptr);
    if (!ip) {
        printf("%%Error: cannot find t.u.i\n");
        return;
    }
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = value;
    vpi_put_value(ip, &val, nullptr, vpiForceFlag);
    vpi_release_handle(ip);
}
