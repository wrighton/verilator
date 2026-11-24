// DESCRIPTION: Verilator: DPI stub for t_virtual_interface_member_trigger
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include VM_PREFIX_INCLUDE_DPI

// Returns a non-null handle
void* dpii_handle() {
    static int s_object;
    return &s_object;
}
