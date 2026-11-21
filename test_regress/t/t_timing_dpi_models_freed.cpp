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

#include <algorithm>
#include <svdpi.h>

extern "C" {
void a_wait();
void b_task();
void a_save_scope();
void b_save_scope();
int a_imp();
int b_imp();
}

static svScope s_aScope = nullptr;  // Scope of model a's exports
static svScope s_bScope = nullptr;  // Scope of model b's exports

void a_save_scope() { s_aScope = svGetScope(); }
void b_save_scope() { s_bScope = svGetScope(); }

int a_imp() {
    svSetScope(s_bScope);
    b_task();
    return 0;
}

int b_imp() {
    svSetScope(s_aScope);
    a_wait();
    return 0;
}

int main() {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    Vb b{contextp.get(), "b"};
    Va a{contextp.get(), "a"};
    b.eval();
    a.eval();
    while (!contextp->gotFinish() && (a.eventsPending() || b.eventsPending())) {
        uint64_t time = ~0ULL;
        if (a.eventsPending()) time = std::min(time, a.nextTimeSlot());
        if (b.eventsPending()) time = std::min(time, b.nextTimeSlot());
        contextp->time(time);
        b.eval();
        a.eval();
    }
    a.final();
    b.final();
    return 0;
}
