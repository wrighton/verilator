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

#include <verilated.h>

#include <memory>
#include <thread>

#include VM_PREFIX_INCLUDE
#include VM_PREFIX_INCLUDE_DPI

// These require the above. Comment prevents clang-format moving them
#include "TestCheck.h"

int errors = 0;

static thread_local int t_count = -1;

void dpii_tick() {
    const int count = dpix_count();
    if (t_count >= 0) TEST_CHECK_EQ(count, t_count + 1);
    t_count = count;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> context0p{new VerilatedContext};
    const std::unique_ptr<VerilatedContext> context1p{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> top0p{new VM_PREFIX{context0p.get(), "top0"}};
    const std::unique_ptr<VM_PREFIX> top1p{new VM_PREFIX{context1p.get(), "top1"}};
    // Two copies of the model, in their own threads, make the first calls of the same export
    const auto sim = [](VM_PREFIX* topp) {
        for (int i = 0; i < 20; ++i) {
            topp->clk = !topp->clk;
            topp->eval();
        }
    };
    std::thread thread0{sim, top0p.get()};
    std::thread thread1{sim, top1p.get()};
    thread0.join();
    thread1.join();
    top0p->final();
    top1p->final();
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
