//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0
//

#include <verilated.h>

#include <cerrno>
#include <memory>

#include VM_PREFIX_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    // A stale error number must not fail a valid argument
    errno = ERANGE;
    contextp->commandArgs(argc, argv);
    // Fails, as the limit is too large
    if (contextp->commandArgsPlusMatch("api_max")[0]) contextp->convergeLimit(2147483648U);
    // Replaces the limit from the command line
    contextp->convergeLimit(100000);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    while (!contextp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
    topp->final();
    return 0;
}
