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

    constexpr int WORDS = 12500;  // Of the 399990-bit input
    for (int i = 0; i < 3; ++i) {
        for (int w = 0; w < WORDS; ++w) topp->in[w] = 0x9e3779b9U * (i + w + 1);
        // Bits above the width of the input, which a harness should leave zero
        topp->in[WORDS - 1] |= 0xffc00000U;
        topp->eval();
        const uint32_t top = (topp->in[WORDS - 1] << 10) | (topp->in[WORDS - 2] >> 22);
        TEST_CHECK_EQ(topp->out, topp->in[0] ^ top);
    }

    topp->final();
    printf("*-* All Finished *-*\n");
    return errors;
}
