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

#include <atomic>
#include <memory>
#include <thread>

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

int main(int argc, char** argv) {
    // The VPI hierarchy of a model may be iterated while models of another thread, on their
    // own context, are created and destroyed
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "a"}};
    const vpiHandle tp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("a.t"), nullptr);
    const vpiHandle up = vpi_handle_by_name(const_cast<PLI_BYTE8*>("a.t.u"), nullptr);
    TEST_CHECK_NZ(tp);
    TEST_CHECK_NZ(up);
    const int modules = scanCount(vpi_iterate(vpiModule, tp));
    const int scopes = scanCount(vpi_iterate(vpiInternalScope, up));
    TEST_CHECK_NE(modules, 0);
    TEST_CHECK_NE(scopes, 0);
    std::atomic<bool> done{false};
    std::thread churn{[&] {
        for (int i = 0; i < 100; ++i) {
            const std::unique_ptr<VerilatedContext> otherContextp{new VerilatedContext};
            const std::unique_ptr<VM_PREFIX> otherTopp{new VM_PREFIX{otherContextp.get(), "b"}};
        }
        done = true;
    }};
    int iterations = 0;
    while (!done) {
        // Iterations started before, and scanned during, the other thread's changes
        const vpiHandle modulesp = vpi_iterate(vpiModule, tp);
        const vpiHandle scopesp = vpi_iterate(vpiInternalScope, up);
        const int moduleCount = scanCount(modulesp);
        const int scopeCount = scanCount(scopesp);
        TEST_CHECK_EQ(moduleCount, modules);
        TEST_CHECK_EQ(scopeCount, scopes);
        ++iterations;
    }
    churn.join();
    TEST_CHECK_NE(iterations, 0);
    vpi_release_handle(up);
    vpi_release_handle(tp);
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
