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
void b_wait();
void b_entry();
void b_entry_wait();
void b_entry_deep();
void a_touch();
unsigned b_rand();
void b_save_scope();
int a_imp(unsigned* drawnp);
int a_imp_nested(unsigned* drawnp, int depth);
int b_imp();
int b_imp_deep();
}

static svScope s_bScope = nullptr;  // Scope of model b's exports
static unsigned s_drawn = 0;  // Value drawn by b_imp

void b_save_scope() { s_bScope = svGetScope(); }

int a_imp(unsigned* drawnp) {
    const svScope aScope = svGetScope();
    svSetScope(s_bScope);
    b_wait();
    *drawnp = b_rand();
    svSetScope(aScope);
    a_touch();
    return 0;
}

int a_imp_nested(unsigned* drawnp, int depth) {
    const svScope aScope = svGetScope();
    svSetScope(s_bScope);
    if (depth == 0) {
        b_entry();
    } else if (depth == 1) {
        b_entry_wait();
    } else {
        b_entry_deep();
    }
    svSetScope(aScope);
    *drawnp = s_drawn;
    return 0;
}

int b_imp() {
    s_drawn = b_rand();
    return 0;
}

int b_imp_deep() {
    b_entry();
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
