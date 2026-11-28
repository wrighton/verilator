// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include <memory>

#include VM_PREFIX_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    // Each model warns of its own stream, whether or not at an address of an earlier one
    for (int i = 0; i < 5; ++i) {
        const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
        topp->n = 2;
        topp->eval();
        if (topp->out != 0x0102) vl_fatal(__FILE__, __LINE__, "top", "Wrong legal result");
        topp->n = 5;
        topp->eval();
        topp->final();
    }
    VL_PRINTF("*-* All Finished *-*\n");
    return 0;
}
