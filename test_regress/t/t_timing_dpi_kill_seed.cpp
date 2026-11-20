// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <svdpi.h>

extern "C" {
void sv_join();
int c_join_in_sv();
}

int c_join_in_sv() {
    sv_join();
    return svIsDisabledState();
}
