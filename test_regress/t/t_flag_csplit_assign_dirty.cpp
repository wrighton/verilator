// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0
//
//*************************************************************************

#include <verilated.h>

#include VM_PREFIX_INCLUDE

#include "TestCheck.h"

int errors = 0;

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};

    for (int i = 0; i < 4; ++i) {
        for (int w = 0; w < 10; ++w) topp->in[w] = 0x12345678U * (i + w + 1);
        // Bits above the width of the input, which a harness should leave zero
        topp->in[9] |= 0xfffff000U;
        topp->eval();
        for (int w = 0; w < 9; ++w) TEST_CHECK_EQ(topp->out[w], ~topp->in[w]);
        TEST_CHECK_EQ(topp->out[9] & 0x1fffU, ~topp->in[9] & 0x1fffU);
    }

    topp->final();
    printf("*-* All Finished *-*\n");
    return errors;
}
