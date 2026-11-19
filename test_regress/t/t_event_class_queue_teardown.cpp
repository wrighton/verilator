// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#include "verilated.h"

#include VM_PREFIX_INCLUDE

#include <memory>

// Evaluate until finished, or up to a time, then destroy the model without final()
static void run(int argc, char** argv, uint64_t endTime) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    topp->eval();
    while (!contextp->gotFinish() && topp->eventsPending()
           && topp->nextTimeSlot() <= endTime) {
        contextp->time(topp->nextTimeSlot());
        topp->eval();
    }
}

int main(int argc, char** argv) {
    // Not finished, with the processes still waiting
    run(argc, argv, 100);
    // Finished while the fired list is still pending
    const char* finishArgv[] = {argc ? argv[0] : "", "+finish"};
    run(2, const_cast<char**>(finishArgv), 1000);
    return 0;
}
