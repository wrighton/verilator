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

#include VM_PREFIX_INCLUDE
#include VM_PREFIX_ROOT_INCLUDE
// The symbol table, through which the test reads the count of reused results
#define T_STR2(x) #x
#define T_STR(x) T_STR2(x)
#define T_CAT2(a, b) a##b
#define T_CAT(a, b) T_CAT2(a, b)
#include T_STR(T_CAT(VM_PREFIX, __Syms).h)

#include <cstdio>
#include <cstdlib>

// The combinational update of a hierarchical block reusing the results of a call with the same
// inputs follows a force, a release and a deposit through the VPI of what drives its input, and
// a write through the VPI of the state of the block

static VM_PREFIX* topp = nullptr;
static int errors = 0;

#define CHECK(got, exp) \
    do { \
        if ((got) != (exp)) { \
            printf("%%Error: line %d: got %d exp %d\n", __LINE__, (int)(got), (int)(exp)); \
            ++errors; \
        } \
    } while (0)

static vpiHandle handle(const char* namep) {
    const vpiHandle objp = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    if (!objp) {
        printf("%%Error: cannot find %s\n", namep);
        std::exit(1);
    }
    return objp;
}

static void put(vpiHandle objp, int value, int flags) {
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = value;
    vpi_put_value(objp, &v, nullptr, flags);
}

static void eval() {
    topp->eval();
    // Again, with the same inputs
    topp->eval();
}

int main(int argc, char** argv) {
    VerilatedContext* const contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    topp = new VM_PREFIX{contextp};
    topp->clk = 0;
    topp->in = 3;
    eval();
    CHECK(topp->o, 3 + 0x10);

    const vpiHandle drvp = handle("TOP.t.drv");
    put(drvp, 7, vpiForceFlag);
    eval();
    CHECK(topp->o, 7 + 0x10);
    topp->in = 4;  // Forced, so no effect
    eval();
    CHECK(topp->o, 7 + 0x10);
    put(drvp, 0, vpiReleaseFlag);
    eval();
    CHECK(topp->o, 4 + 0x10);

    // A clock update
    topp->clk = 1;
    eval();
    CHECK(topp->q, 4);
    CHECK(topp->o, 4 + 0x11);
    topp->clk = 0;
    eval();
    CHECK(topp->o, 4 + 0x11);

    // A write of the block's state with the same inputs
    put(handle("TOP.t.u.st"), 0x40, vpiNoDelay);
    eval();
    CHECK(topp->o, 4 + 0x40);

    // A deposit of what drives the input, which, as in a flat model, takes effect only through
    // the assignment when its input changes
    put(drvp, 9, vpiNoDelay);
    eval();
    CHECK(topp->o, 4 + 0x40);
    topp->in = 5;
    eval();
    CHECK(topp->o, 5 + 0x40);

    // Most of the evaluations above had the same inputs
    const uint64_t skipped = topp->rootp->vlSymsp->vlInst.TOP__t__DOT__u.__Vnontrivs
                                 .__Vdpicache_sub_protectlib_combo_update.skippedCount();
    printf("Combinational updates reusing results: %d\n", static_cast<int>(skipped));
    if (skipped < 5) {
        printf("%%Error: too few combinational updates reused results\n");
        ++errors;
    }

    topp->final();
    delete topp;
    delete contextp;
    if (errors) return 1;
    printf("*-* All Finished *-*\n");
    return 0;
}
