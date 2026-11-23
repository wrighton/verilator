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

#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <thread>

// After writes through the VPI with clock edges, each instance of a library is evaluated by one
// thread at a time

static std::atomic<int> evaluating[3];  // Of instances u1 and u2
static std::atomic<int> overlaps{0};  // Evaluations of an instance by two threads at once

extern "C" void sub_evaluated(int id, int /*unused*/) {
    if (id != 1 && id != 2) return;
    if (evaluating[id]++) ++overlaps;
    std::this_thread::sleep_for(std::chrono::microseconds{200});
    --evaluating[id];
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    topp->clk = 0;
    topp->drv = 0x11;
    topp->eval();
    const vpiHandle op = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.t.u1.o"), nullptr);
    if (!op) {
        printf("%%Error: cannot find top.t.u1.o\n");
        return 1;
    }
    for (int k = 0; k < 100; ++k) {
        s_vpi_value val;
        val.format = vpiIntVal;
        val.value.integer = k;
        vpi_put_value(op, &val, nullptr, (k & 1) ? vpiForceFlag : vpiReleaseFlag);
        topp->clk = !topp->clk;
        topp->eval();
        const int exp = (k & 1) ? k : 0x11;
        if (topp->o1 != exp) {
            printf("%%Error: o1: got='h%02x exp='h%02x\n", topp->o1, exp);
            return 1;
        }
    }
    if (overlaps) {
        printf("%%Error: %d overlapping evaluations\n", overlaps.load());
        return 1;
    }
    topp->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
