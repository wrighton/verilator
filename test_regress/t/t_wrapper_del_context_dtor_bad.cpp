// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Multiple Model Test Module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include VM_PREFIX_INCLUDE

#include <memory>

// A model owned by a static object destroyed at exit
std::unique_ptr<VM_PREFIX> g_topp;

int main(int argc, char** argv) {
    VerilatedContext* const contextp{new VerilatedContext};
    g_topp.reset(new VM_PREFIX{contextp, "TOP"});
    g_topp->eval();

    // Ideally we'd do this, but then address sanitizer blows up
    // delete contextp;  // Test mistake - deleting contextp before its model
    contextp->selfTestClearMagic();

    return 0;
}
