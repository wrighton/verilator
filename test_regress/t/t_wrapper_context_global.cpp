// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Multiple Model Test Module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include VM_PREFIX_INCLUDE

#include <cstdio>
#include <memory>

// A model on the default context, owned by a static object destroyed at exit
std::unique_ptr<VM_PREFIX> g_topp;

static void endContextCb(void*) {
    std::printf("End of the default context\n");
    std::fflush(stdout);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    // Runs at exit, though the default context is never destroyed
    Verilated::defaultContextp()->addEndContextCb(endContextCb, nullptr);
    g_topp.reset(new VM_PREFIX);
    while (!Verilated::gotFinish()) {
        g_topp->clk = !g_topp->clk;
        g_topp->eval();
    }
    g_topp->final();
    return 0;
}
