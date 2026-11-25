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

#include "Vt_dpi_cache__Dpi.h"
#include "svdpi.h"

static int s_sumCalls = 0;
static int s_inoutCalls = 0;
static int s_openCalls = 0;

int dpic_sum(int a, const int* arr, int* calls) {
    *calls = ++s_sumCalls;
    return a + arr[0] + arr[1];
}
int dpic_inout(int* a) {
    *a = *a + 1;
    return ++s_inoutCalls;
}
int dpic_open(const svOpenArrayHandle /*arr*/) { return ++s_openCalls; }
static int s_declCalls = 0;
int dpic_decl(int a) { return a * 100 + ++s_declCalls; }
