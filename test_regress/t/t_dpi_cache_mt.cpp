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

#include VM_PREFIX_INCLUDE
#include "Vt_dpi_cache_mt__Dpi.h"
#include "svdpi.h"

#include <cstdio>
#include <memory>

int dpic_mt(int x, int* payload) {
    for (int i = 0; i < 4096; ++i) payload[i] = x;
    return x;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->threads(4);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    int errors = 0;
    topp->clk = 0;
    topp->eval();
    for (int cyc = 0; cyc < 400; ++cyc) {
        // Each caller with its own inputs, the same for a few cycles
        const int base = cyc / 4;
        topp->x0 = 10 + base;
        topp->x1 = 20 + base;
        topp->x2 = 30 + base;
        topp->x3 = 40 + base;
        topp->clk = 1;
        topp->eval();
        if (topp->y0 != 10 + base || topp->y1 != 20 + base || topp->y2 != 30 + base
            || topp->y3 != 40 + base) {
            printf("%%Error: cycle %d: got %d %d %d %d\n", cyc, topp->y0, topp->y1, topp->y2,
                   topp->y3);
            if (++errors > 5) break;
        }
        topp->clk = 0;
        topp->eval();
    }
    topp->final();
    if (errors) return 1;
    printf("*-* All Finished *-*\n");
    return 0;
}
