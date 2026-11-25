// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include <cstdio>

#include VM_PREFIX_INCLUDE

static VerilatedContext* s_contextp = nullptr;

extern "C" void addarg() {
    static const char* argv[] = {"+reviewflag=41"};
    s_contextp->commandArgsAdd(1, argv);
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    s_contextp = contextp.get();
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    // The clock is driven from outside, so its edge starts the time step
    topp->clk = 0;
    topp->eval();
    contextp->timeInc(1);
    topp->clk = 1;
    topp->eval();
    if (topp->got_test != 1 || topp->got_value != 41) {
        std::printf("%%Error: got_test=%d got_value=%d, expected 1 41\n", topp->got_test,
                    topp->got_value);
        return 1;
    }
    topp->final();
    std::printf("*-* All Finished *-*\n");
    return 0;
}
