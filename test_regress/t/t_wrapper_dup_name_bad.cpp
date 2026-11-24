//
// DESCRIPTION: Verilator: Verilog Multiple Model Test Module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include VM_PREFIX_INCLUDE

// Destroyed when the error exits
std::unique_ptr<VerilatedContext> s_contextp;
std::unique_ptr<VM_PREFIX> s_firstp;

int main() {
    s_contextp.reset(new VerilatedContext);

    // Two models under the same hierarchical path in one context
    s_firstp.reset(new VM_PREFIX{s_contextp.get(), "TOP"});
    const std::unique_ptr<VM_PREFIX> secondp{new VM_PREFIX{s_contextp.get(), "TOP"}};

    return 0;
}
