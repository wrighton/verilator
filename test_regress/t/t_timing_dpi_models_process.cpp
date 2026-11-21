// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include "Va.h"
#include "Vb.h"

static Vb* s_bp = nullptr;  // Model evaluated from model a
static int s_bObjects = 0;  // Objects model b created

extern "C" void eval_b() { s_bp->eval(); }
extern "C" void b_created() { ++s_bObjects; }
extern "C" int b_objects() { return s_bObjects; }

int main() {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    Vb b{contextp.get(), "b"};
    s_bp = &b;
    Va a{contextp.get(), "a"};
    b.eval();
    a.eval();
    while (!contextp->gotFinish() && a.eventsPending()) {
        contextp->time(a.nextTimeSlot());
        a.eval();
    }
    a.final();
    b.final();
    return 0;
}
