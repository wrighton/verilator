// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include "TestCheck.h"

#include <memory>
#include VM_PREFIX_INCLUDE
#include VM_PREFIX_ROOT_INCLUDE

int errors = 0;
static VM_PREFIX* s_topp = nullptr;
static bool s_cross = false;
static int s_calls = 0;

// Change the variable the caller reads, or with +cross the one the other caller reads
extern "C" int cxx_from(int which, int value) {
    ++s_calls;
    auto* const rootp = s_topp->rootp;
    if ((which == 0) != s_cross) {
        ++rootp->t__DOT__pubA;
    } else {
        ++rootp->t__DOT__pubB;
    }
    return value;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    s_cross = contextp->commandArgsPlusMatch("cross")[0];
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    s_topp = topp.get();
    topp->in = 1;
    topp->eval();
    const int settleCalls = s_calls;
    topp->in = 2;
    topp->eval();
    // Each evaluation calls each reader once
    TEST_CHECK_EQ(s_calls - settleCalls, 2);
    s_topp->rootp->t__DOT__pubC = 5;
    topp->eval();
    TEST_CHECK_EQ(topp->obsC, 6);
    topp->final();
    return errors ? 10 : 0;
}
