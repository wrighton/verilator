// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: svGetScopeFromName finds a package by its own name in a DPI task
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <svdpi.h>

extern "C" int p_wait();
extern "C" int dpic_task();

static void checkPackage() {
    const svScope scope = svGetScopeFromName("p");
    if (!scope || std::strcmp(svGetNameFromScope(scope), "TOP.p")) {
        printf("%%Error: package scope '%s'\n", scope ? svGetNameFromScope(scope) : "<none>");
        exit(1);
    }
}

// The task runs on another thread while the export waits, which keeps the scope set
int dpic_task() {
    checkPackage();
    const svScope prevScope = svSetScope(svGetScopeFromName("p"));
    p_wait();
    svSetScope(prevScope);
    checkPackage();
    return 0;
}
