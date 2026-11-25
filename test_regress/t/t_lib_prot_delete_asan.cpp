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

#include <cstdio>
#include <memory>

extern "C" void* sub_protectlib_create(const char* scopep__V);
extern "C" void sub_protectlib_delete(void* vhandlep__V);

static void* s_libp = nullptr;
static void deleteLib(void*) { sub_protectlib_delete(s_libp); }
static void createLib(void*) { sub_protectlib_create("top.w"); }

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    Verilated::threadContextp(contextp.get());
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    // A library model created and deleted through its C interface, as by its wrapper in another
    // simulator, is then not deleted again with the context
    sub_protectlib_delete(sub_protectlib_create("top.u"));
    // Also when deleted by a callback run as the context is destroyed, before its own
    contextp->addEndContextCb(deleteLib, nullptr);
    s_libp = sub_protectlib_create("top.v");
    // And when created by a callback run as the context is destroyed, which deletes it then
    contextp->addEndContextCb(createLib, nullptr);
    topp->eval();
    topp->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
