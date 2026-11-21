// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#include "verilated.h"

#include "vpi_user.h"

// These require the above. Comment prevents clang-format moving them
#include "TestCheck.h"
#include "TestVpi.h"

int errors = 0;

//======================================================================

// Check the parameters of an instance are only those it declares
static void check_params(const char* scopeName) {
    TestVpiHandle scopeh = vpi_handle_by_name(const_cast<PLI_BYTE8*>(scopeName), nullptr);
    TEST_CHECK_NZ(scopeh);
    if (!scopeh) return;
    TestVpiHandle iter = vpi_iterate(vpiParameter, scopeh);
    TEST_CHECK_NZ(iter);
    if (!iter) return;
    int count = 0;
    while (TestVpiHandle paramh = vpi_scan(iter)) {
        ++count;
        TEST_CHECK_CSTR(vpi_get_str(vpiName, paramh), "W");
    }
    iter.freed();  // IEEE 37.2.2 vpi_scan at end does a vpi_release_handle
    TEST_CHECK_EQ(count, 1);
}

extern "C" int mon_check() {
    check_params("t.u_bound");
    check_params("t.u_other");
    // The bound instance is visible, with its parameter
    TestVpiHandle idh
        = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.u_bound.u_probe.ID"), nullptr);
    TEST_CHECK_NZ(idh);
    return errors;
}
