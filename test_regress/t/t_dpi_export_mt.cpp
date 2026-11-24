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

#include <atomic>
#include <memory>
#include <thread>

#include VM_PREFIX_INCLUDE
#include VM_PREFIX_INCLUDE_DPI
#include "Vt_dpi_export_mt_other.h"

// These require the above. Comment prevents clang-format moving them
#include "TestCheck.h"

int errors = 0;

// Accessed relaxed, so ThreadSanitizer sees no ordering between the threads' DPI accesses
static std::atomic<bool> s_called{false};
static std::atomic<bool> s_constructed{false};

static int s_count = -1;  // Used only by the thread of the model calling exports

void dpii_tick() {
    TEST_CHECK_EQ(dpix_sub(), 5);
    const int count = dpix_count();
    if (s_count >= 0) TEST_CHECK_EQ(count, s_count + 1);
    s_count = count;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> callContextp{new VerilatedContext};
    const std::unique_ptr<VerilatedContext> constructContextp{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{callContextp.get(), "top"}};
    // One thread calls exports of its model, from its own and another scope, while another
    // constructs a model with new exports
    std::thread callThread{[&] {
        while (!s_constructed.load(std::memory_order_relaxed)) {
            topp->clk = !topp->clk;
            topp->eval();
            if (s_count > 10) s_called.store(true, std::memory_order_relaxed);
        }
    }};
    std::thread constructThread{[&] {
        while (!s_called.load(std::memory_order_relaxed)) std::this_thread::yield();
        const std::unique_ptr<Vt_dpi_export_mt_other> otherp{
            new Vt_dpi_export_mt_other{constructContextp.get(), "other"}};
        s_constructed.store(true, std::memory_order_relaxed);
        otherp->final();
    }};
    constructThread.join();
    callThread.join();
    topp->final();
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
