// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"
#include "verilated_random.h"

#include <thread>

#include VM_PREFIX_INCLUDE

// The first outermost call of each of two threads, one after the other
extern "C" int stamps_differ_over_threads() {
    uint64_t stamps[2] = {0, 0};
    for (int i = 0; i < 2; ++i) {
        std::thread thread{[&stamps, i] {
            VlRandomizeCall::enter();
            stamps[i] = VlRandomizeCall::stamp();
            VlRandomizeCall::exit();
        }};
        thread.join();
    }
    return stamps[0] != stamps[1];
}
