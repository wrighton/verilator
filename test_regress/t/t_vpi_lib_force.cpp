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
#include VM_PREFIX_INCLUDE_DPI

#include <cstdio>
#include <cstdlib>
#include <memory>

// A force and a release through the VPI of a port of the instance of a library take effect
// without a change in the model using it, as in a flat model, evaluating only that instance

static VM_PREFIX* topp = nullptr;
static int errors = 0;
static int evaluations[3] = {0, 0, 0};  // Of instances u1 and u2

extern "C" void sub_evaluated(int id, int /*unused*/) {
    if (id == 1 || id == 2) ++evaluations[id];
}

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

    topp->clk = 0;
    topp->drv = 0x11;
    topp->sel = 1;
    topp->eval();
    const vpiHandle ip = handle("top.t.u1.i");
    const vpiHandle op = handle("top.t.u1.o");
    const vpiHandle clkp = handle("top.t.u1.clk");
    check("initial", topp->out1, 0x11);
    check("initial u2", topp->out2, 0x6e);

    // A force of the input holds while its driver changes, until released
    put(ip, 0x25, vpiForceFlag);
    topp->eval();
    check("force i", topp->out1, 0x25);
    check("force i, i", get(ip), 0x25);
    check("force i, o", get(op), 0x25);
    check("force i, u2", topp->out2, 0x6e);
    topp->drv = 0x22;
    topp->eval();
    check("force i, drv changes", topp->out1, 0x25);
    put(ip, 0, vpiReleaseFlag);
    topp->eval();
    check("release i", topp->out1, 0x22);
    check("release i, i", get(ip), 0x22);
    topp->drv = 0x33;
    topp->eval();
    check("released i, drv changes", topp->out1, 0x33);

    // Likewise a force of the output
    put(op, 0x43, vpiForceFlag);
    topp->eval();
    check("force o", topp->out1, 0x43);
    check("force o, o", get(op), 0x43);
    topp->drv = 0x44;
    topp->eval();
    check("force o, drv changes", topp->out1, 0x43);
    put(op, 0, vpiReleaseFlag);
    topp->eval();
    check("release o", topp->out1, 0x44);

    // A force and another input change in one evaluation, without an edge
    put(ip, 0x3c, vpiForceFlag);
    topp->sel = 2;
    topp->eval();
    check("force i with sel", topp->out1, 0x3c);
    check("force i with sel, m", topp->m1, 0x03);
    put(ip, 0, vpiReleaseFlag);
    topp->sel = 1;
    topp->eval();
    check("release i with sel", topp->out1, 0x44);
    check("release i with sel, m", topp->m1, 0x02);

    // A force of a clock makes an edge where the instance sees all its inputs
    topp->drv = 0x11;
    topp->eval();
    const int n = topp->n1;
    put(clkp, 1, vpiForceFlag);
    topp->eval();
    check("force clk", topp->n1, (n + 1) & 0x7f);
    check("force clk, q", topp->q1, 0x11);
    // Released while its driver stays low, it makes no edge
    put(clkp, 0, vpiReleaseFlag);
    topp->eval();
    check("release clk low", topp->n1, (n + 1) & 0x7f);
    // Held low while its driver rises and the data changes, then released, it makes an edge
    put(clkp, 0, vpiForceFlag);
    topp->clk = 1;
    topp->eval();
    check("hold clk low, driver rises", topp->n1, (n + 1) & 0x7f);
    topp->drv = 0x47;
    topp->eval();
    check("hold clk low, data changes", topp->n1, (n + 1) & 0x7f);
    put(clkp, 0, vpiReleaseFlag);
    topp->eval();
    check("release clk high", topp->n1, (n + 2) & 0x7f);
    check("release clk high, q", topp->q1, 0x47);
    topp->clk = 0;
    topp->eval();
    // The edge a write makes in the same evaluation as a change of an input of the library
    // evaluated with its clocks may see the previous value of that input, as documented

    // A write into an unrelated register, with a data change and an edge in one evaluation: the
    // flop sampling a combinational output sees the new data
    topp->clk = 0;
    topp->eval();
    const vpiHandle np = handle("top.t.u1.n");
    put(np, 0x05, vpiNoDelay);
    topp->sel = 2;
    topp->clk = 1;
    topp->eval();
    check("deposit n with sel and edge, sm1", topp->sm1, 0x03);
    topp->sel = 1;
    topp->clk = 0;
    topp->eval();

    // A write into a library instance without a clock, fed from a flop
    topp->clk = 1;
    topp->eval();
    topp->clk = 0;
    topp->eval();
    const int y = topp->drv & 3;
    check("cmb", topp->zc, (y + 9 + topp->drv) & 0x7f);
    put(vpi_handle_by_index(handle("top.t.c.memc"), y), 0x20, vpiNoDelay);
    topp->eval();
    check("write memc", topp->zc, (0x20 + topp->drv) & 0x7f);

    // A write of a whole array
    const vpiHandle memp = handle("top.t.u1.mem");
    PLI_INT32 values[4] = {0x31, 0x32, 0x33, 0x34};
    s_vpi_arrayvalue arrayValue;
    arrayValue.format = vpiIntVal;
    arrayValue.flags = 0;
    arrayValue.value.integers = values;
    PLI_INT32 indexes[1] = {0};
    vpi_put_value_array(memp, &arrayValue, indexes, 4);
    topp->eval();
    check("put array", topp->m1, 0x32);

    // Likewise a force of a port of a library instance without a clock within one
    const vpiHandle lp = handle("top.t.u1.l.i");
    check("leaf", topp->leaf1, 0x39);
    put(lp, 0x5a, vpiForceFlag);
    topp->eval();
    check("force leaf i", topp->leaf1, 0x5b);
    topp->drv = 0x66;
    topp->eval();
    check("force leaf i, drv changes", topp->leaf1, 0x5b);
    topp->sel = 3;
    topp->eval();
    check("force leaf i, sel changes", topp->leaf1, 0x59);
    put(lp, 0, vpiReleaseFlag);
    topp->eval();
    check("release leaf i", topp->leaf1, 0x1a);
    put(lp, 0x2d, vpiForceFlag);
    topp->sel = 1;
    topp->eval();
    check("force leaf i with sel", topp->leaf1, 0x2c);
    put(lp, 0, vpiReleaseFlag);
    topp->eval();
    check("release leaf i with sel", topp->leaf1, 0x18);

#ifndef T_FLAT
    // An unrelated export evaluates no instance, and a write through the VPI evaluates only
    // the written instance, beyond the evaluations of an evaluation without them
    svSetScope(svGetScopeFromName("top.t"));
    int evaluations1 = evaluations[1];
    int evaluations2 = evaluations[2];
    topp->eval();
    const int idle1 = evaluations[1] - evaluations1;
    const int idle2 = evaluations[2] - evaluations2;
    for (int k = 0; k < 10; ++k) {
        evaluations1 = evaluations[1];
        evaluations2 = evaluations[2];
        tb_set(k);
        topp->eval();
        check("export, u1 evaluations", evaluations[1] - evaluations1, idle1);
        check("export, u2 evaluations", evaluations[2] - evaluations2, idle2);
    }
    check("export", topp->tbo, 10);
    evaluations2 = evaluations[2];
    put(ip, 0x2b, vpiForceFlag);
    topp->eval();
    check("force i, u1", topp->out1, 0x2b);
    check("force i, u2 evaluations", evaluations[2] - evaluations2, idle2);
    put(ip, 0, vpiReleaseFlag);
    topp->eval();
#endif

    // A write after the model using a library is deleted, while the library model remains
    topp->final();
    delete topp;
    topp = nullptr;
    const vpiHandle afterp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.t.u1.l.i"), nullptr);
    if (afterp) put(afterp, 0x15, vpiForceFlag);

    if (errors) return 1;
    printf("*-* All Finished *-*\n");
    return 0;
}
