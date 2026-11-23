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

#include <cstdio>
#include <cstdlib>

// A force and a release through the VPI of a port of the instance of a library take effect
// without a change in the model using it, as in a flat model

static VM_PREFIX* topp = nullptr;
static int errors = 0;

static vpiHandle handle(const char* namep) {
    const vpiHandle objp = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    if (!objp) {
        printf("%%Error: cannot find %s\n", namep);
        std::exit(1);
    }
    return objp;
}

static int get(vpiHandle objp) {
    s_vpi_value val;
    val.format = vpiIntVal;
    vpi_get_value(objp, &val);
    return val.value.integer;
}

static void put(vpiHandle objp, int value, int flags) {
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = value;
    vpi_put_value(objp, &val, nullptr, flags);
}

static void check(const char* whatp, int got, int exp) {
    if (got == exp) return;
    printf("%%Error: %s: got='h%02x exp='h%02x\n", whatp, got, exp);
    ++errors;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    topp = new VM_PREFIX{contextp.get(), "top"};

    topp->drv = 0x11;
    topp->eval();
    const vpiHandle ip = handle("top.t.u.i");
    const vpiHandle op = handle("top.t.u.o");
    check("initial", topp->out, 0x11);

    // A force of the input holds while its driver changes, until released
    put(ip, 0xa5, vpiForceFlag);
    topp->eval();
    check("force i", topp->out, 0xa5);
    check("force i, i", get(ip), 0xa5);
    check("force i, o", get(op), 0xa5);
    topp->drv = 0x22;
    topp->eval();
    check("force i, drv changes", topp->out, 0xa5);
    put(ip, 0, vpiReleaseFlag);
    topp->eval();
    check("release i", topp->out, 0x22);
    check("release i, i", get(ip), 0x22);
    topp->drv = 0x33;
    topp->eval();
    check("released i, drv changes", topp->out, 0x33);

    // Likewise a force of the output
    put(op, 0xc3, vpiForceFlag);
    topp->eval();
    check("force o", topp->out, 0xc3);
    check("force o, o", get(op), 0xc3);
    topp->drv = 0x44;
    topp->eval();
    check("force o, drv changes", topp->out, 0xc3);
    put(op, 0, vpiReleaseFlag);
    topp->eval();
    check("release o", topp->out, 0x44);

    // Likewise a force of a port of a library instance within one
    const vpiHandle lp = handle("top.t.u.l.i");
    check("leaf", topp->out2, 0xbb);
    put(lp, 0x5a, vpiForceFlag);
    topp->eval();
    check("force leaf i", topp->out2, 0x5a);
    topp->drv = 0x55;
    topp->eval();
    check("force leaf i, drv changes", topp->out2, 0x5a);
    put(lp, 0, vpiReleaseFlag);
    topp->eval();
    check("release leaf i", topp->out2, 0xaa);

    topp->final();
    delete topp;
    if (errors) return 1;
    printf("*-* All Finished *-*\n");
    return 0;
}
