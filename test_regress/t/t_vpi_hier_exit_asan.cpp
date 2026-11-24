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
#include "verilated_vpi.h"

#include "TestCheck.h"
#include VM_PREFIX_INCLUDE

#include <cstdlib>
#include <memory>

int errors = 0;

#ifdef T_GLOBAL_CONTEXT
// A context owned by a static object, destroyed at exit
std::unique_ptr<VerilatedContext> g_contextp;
#endif

int main(int argc, char** argv) {
    // Exits cleanly when the context of a model with hierarchical blocks is destroyed at exit
#ifdef T_GLOBAL_CONTEXT
    g_contextp.reset(new VerilatedContext);
    g_contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{g_contextp.get(), ""}};
#else
    Verilated::commandArgs(argc, argv);  // The default context
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{""}};
#endif
    for (int i = 0; i < 10; ++i) {
        topp->clk = i & 1;
        topp->eval();
    }
    TEST_CHECK_EQ(topp->q0, 5);
    TEST_CHECK_EQ(topp->q1, 5);
#ifdef T_STD_EXIT
    // Also when exiting with the model alive
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    std::exit(errors ? 10 : 0);
#endif
    topp->final();
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
