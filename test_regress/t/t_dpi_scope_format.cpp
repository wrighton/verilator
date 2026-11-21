// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0
//
//*************************************************************************

#include "Vt_dpi_scope_format__Dpi.h"
#include "svdpi.h"

#include <cstdio>

void dpic_context() { printf("context: %s\n", svGetNameFromScope(svGetScope())); }

void dpic_scopes() {
    static const char* const namesp[]
        = {"t.u1", "t.u1.run", "t.u1.run.named", "t.u2.run.named", "t.i1", "t.i1.name", "t.u_ctx"};
    for (const char* namep : namesp) {
        const svScope scope = svGetScopeFromName(namep);
        printf("%s: %s\n", namep, scope ? svGetNameFromScope(scope) : "<none>");
    }
}
