// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilatedos.h"

#include "verilated.h"

#include <memory>

#include VM_PREFIX_INCLUDE
#include VM_PREFIX_ROOT_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    bool forced = false;
    while (!contextp->gotFinish()) {
        topp->eval();
        if (!forced && contextp->time() >= 3) {
            // Force all bits of 'x' from C++
            topp->rootp->t__DOT__x__VforceVal = 0xee;
            topp->rootp->t__DOT__x__VforceEn = 0xff;
            forced = true;
            topp->eval();
        }
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
    topp->final();
    return 0;
}
