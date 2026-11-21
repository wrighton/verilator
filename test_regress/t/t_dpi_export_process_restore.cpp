// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include <svdpi.h>

extern "C" {
void sv_retain_self();
void sv_kill_joined_child();
void c_save_scope();
int c_current_restored();
void c_kill_joined_child();
}

static svScope s_scope = nullptr;  // Scope of the exported functions
static bool s_restored = false;  // Whether the current process was the same after the call

void c_save_scope() { s_scope = svGetScope(); }
int c_current_restored() { return s_restored; }
void c_kill_joined_child() { sv_kill_joined_child(); }

// Called from $c, so the export has no importing process
void c_call_export_directly() {
    VlProcess* const beforep = VlProcess::currentp();
    svSetScope(s_scope);
    sv_retain_self();
    s_restored = VlProcess::currentp() == beforep;
}
