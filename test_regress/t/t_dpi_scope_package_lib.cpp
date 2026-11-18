// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: svGetScopeFromName finds a package of a library by its own name
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include <cstdio>
#include <memory>
#include <svdpi.h>

#include VM_PREFIX_INCLUDE

extern "C" void dpic_lib_check(const char* whichp);

// The package found is the one the import is called from, of the library or of the model
void dpic_lib_check(const char* whichp) {
    const svScope pkgScope = svGetScopeFromName("q");
    printf("%s: %s %s\n", whichp, pkgScope ? svGetNameFromScope(pkgScope) : "<none>",
           pkgScope == svGetScope() ? "own" : "other");
}

int main() {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    Verilated::threadContextp(contextp.get());
    topp->eval();
    printf("*-* All Finished *-*\n");
    return 0;
}
