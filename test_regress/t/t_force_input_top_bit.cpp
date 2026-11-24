// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include VM_PREFIX_INCLUDE

#include <cassert>
#include <cstdio>

int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    VM_PREFIX top{&context};
    top.rhs = 0;
    top.take = 0;
    top.drop = 0;
    top.eval();
    assert(top.value == 1 && !top.floating);
    top.take = 1;
    top.eval();
    assert(top.value == 0 && !top.floating);
    top.rhs = 1;
    top.eval();
    assert(top.value == 1 && !top.floating);
    top.rhs = 0;
    top.eval();
    assert(top.value == 0 && !top.floating);
    top.drop = 1;
    top.eval();
    assert(top.value == 1 && !top.floating);
    top.final();
    std::puts("*-* All Finished *-*");
    return 0;
}
