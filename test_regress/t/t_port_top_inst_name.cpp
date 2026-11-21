// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include VM_PREFIX_INCLUDE

// These require the above. Comment prevents clang-format moving them
#include "TestCheck.h"

int errors = 0;

int main(int argc, char* argv[]) {
    Verilated::debug(0);
    Verilated::commandArgs(argc, argv);

    VM_PREFIX* topp = new VM_PREFIX{""};

    // Ports named like an instance under the model's top are prefixed by their module name
    topp->t__02Epkg = 5;
    topp->eval();
    TEST_CHECK_EQ(topp->t__02Et, 2);
    topp->t__02Epkg = 1;
    topp->eval();
    TEST_CHECK_EQ(topp->t__02Et, 6);

    topp->final();
    VL_DO_DANGLING(delete topp, topp);

    printf("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
