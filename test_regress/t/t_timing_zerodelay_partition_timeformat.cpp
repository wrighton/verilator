// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include <cstdio>

#include VM_PREFIX_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    // The clock is driven from outside, so its edge starts the time step
    topp->clk = 0;
    topp->eval();
    contextp->timeInc(1000);
    topp->clk = 1;
    topp->eval();
    if (topp->text != "42NEW") {
        std::printf("%%Error: text='%s', expected '42NEW'\n", topp->text.c_str());
        return 1;
    }
    topp->final();
    std::printf("*-* All Finished *-*\n");
    return 0;
}
