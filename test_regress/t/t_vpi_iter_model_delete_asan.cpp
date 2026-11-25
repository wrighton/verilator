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
#include "verilated_vpi.h"

#include "TestCheck.h"
#include VM_PREFIX_INCLUDE

#include <memory>

int errors = 0;

static int scanCount(vpiHandle iterp) {
    int count = 0;
    if (!iterp) return count;
    while (const vpiHandle objp = vpi_scan(iterp)) {
        ++count;
        vpi_release_handle(objp);
    }
    return count;
}

// Start an iteration of the given type on the named object, scanning 'skip' objects
static vpiHandle startIterate(PLI_INT32 type, const char* namep, int skip) {
    const vpiHandle objp = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    TEST_CHECK_NZ(objp);
    const vpiHandle iterp = vpi_iterate(type, objp);
    TEST_CHECK_NZ(iterp);
    // The iteration does not hold the object
    vpi_release_handle(objp);
    for (int i = 0; i < skip; ++i) vpi_release_handle(vpi_scan(iterp));
    return iterp;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextAp{new VerilatedContext};
    const std::unique_ptr<VerilatedContext> contextBp{new VerilatedContext};
    contextAp->commandArgs(argc, argv);
    std::unique_ptr<VM_PREFIX> topAp{new VM_PREFIX{contextAp.get(), "a"}};
    std::unique_ptr<VM_PREFIX> topBp;

    {
        // Iterations are not affected by another model being destroyed
        const int scopes = scanCount(startIterate(vpiInternalScope, "a.t.u", 0));
        const int vars = scanCount(startIterate(vpiReg, "a.t.u", 0));
        TEST_CHECK_NE(scopes, 0);
        TEST_CHECK_NE(vars, 0);
        topBp.reset(new VM_PREFIX{contextBp.get(), "b"});
        Verilated::threadContextp(contextAp.get());  // Names are looked up in this context
        const vpiHandle scopesp = startIterate(vpiInternalScope, "a.t.u", 0);
        const vpiHandle varsp = startIterate(vpiReg, "a.t.u", 0);
        const vpiHandle elementsp = startIterate(vpiReg, "a.t.u.arr", 0);
        const vpiHandle membersp = startIterate(vpiMember, "a.t.u.pair", 0);
        topBp.reset();
        int count = scanCount(scopesp);
        TEST_CHECK_EQ(count, scopes);
        count = scanCount(varsp);
        TEST_CHECK_EQ(count, vars);
        count = scanCount(elementsp);
        TEST_CHECK_EQ(count, 3);
        count = scanCount(membersp);
        TEST_CHECK_EQ(count, 2);
    }

    {
        // Iterations end when the model of the object iterated is destroyed
        const vpiHandle scopesp = startIterate(vpiInternalScope, "a.t.u", 0);
        const vpiHandle varsp = startIterate(vpiReg, "a.t.u", 1);
        const vpiHandle elementsp = startIterate(vpiReg, "a.t.u.arr", 1);
        const vpiHandle membersp = startIterate(vpiMember, "a.t.u.pair", 1);
        topAp.reset();
        int count = scanCount(scopesp);
        TEST_CHECK_EQ(count, 0);
        count = scanCount(varsp);
        TEST_CHECK_EQ(count, 0);
        count = scanCount(elementsp);
        TEST_CHECK_EQ(count, 0);
        count = scanCount(membersp);
        TEST_CHECK_EQ(count, 0);
    }

    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
