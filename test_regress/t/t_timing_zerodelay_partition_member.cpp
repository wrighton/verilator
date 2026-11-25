// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include VM_PREFIX_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    // The clock is driven from outside, so its edges start the time steps
    for (int i = 0; i < 10 && !contextp->gotFinish(); ++i) {
        topp->clk = i & 1;
        topp->eval();
        contextp->timeInc(1);
    }
    topp->final();
    return 0;
}
