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

#include "svdpi.h"

#include VM_PREFIX_INCLUDE

// The headers of the root and of module 't', named after the model
#define STRINGIFY_(x) #x
#define MODEL_HEADER_(prefix, suffix) STRINGIFY_(prefix##suffix.h)
#define MODEL_HEADER(prefix, suffix) MODEL_HEADER_(prefix, suffix)
#include MODEL_HEADER(VM_PREFIX, ___024root)
#include MODEL_HEADER(VM_PREFIX, _t)

#include <memory>

static VM_PREFIX* s_topp = nullptr;

#ifdef T_XKILL
// Calls a DPI export task, then a public function of the model, which fires an event
extern "C" void dpix_wait();
extern "C" int dpii_call_export() {
    dpix_wait();
    s_topp->rootp->t->fire_public();
    return svIsDisabledState();
}
#else
// Calls a public function of the model, which fires an event
extern "C" void dpii_call_public() { s_topp->rootp->t->fire_public(); }
#endif

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    s_topp = topp.get();
    topp->eval();
    while (!contextp->gotFinish() && topp->eventsPending()) {
        contextp->time(topp->nextTimeSlot());
        topp->eval();
    }
    topp->final();
    return 0;
}
