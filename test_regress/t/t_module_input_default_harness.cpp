// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include <memory>
#include VM_PREFIX_INCLUDE

#include "TestCheck.h"

int errors = 0;

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    // Each model has the defaults once constructed, before any evaluation
    const std::unique_ptr<VM_PREFIX> ap{new VM_PREFIX{contextp.get(), "a"}};
    const std::unique_ptr<VM_PREFIX> bp{new VM_PREFIX{contextp.get(), "b"}};
    TEST_CHECK_EQ(static_cast<int>(ap->dflt_i), 9);
    TEST_CHECK_EQ(static_cast<int>(ap->set_i), 9);
    TEST_CHECK_EQ(static_cast<int>(bp->set_i), 9);
    TEST_CHECK_EQ(static_cast<int>(ap->arr_dflt_i[0]), 1);
    TEST_CHECK_EQ(static_cast<int>(ap->arr_dflt_i[1]), 2);
    // The X bits are zero, as --x-assign unique does not apply to a constant expression
    TEST_CHECK_EQ(static_cast<int>(ap->x_i), 0x45);
    // A value written before the first evaluation replaces the default
    ap->set_i = 5;
    ap->arr_set_i[0] = 3;
    ap->arr_set_i[1] = 0;
    // Z bits of a default are a value, which the X and Z bits take as 0, not a driver
    ap->z_set_i = 5;
    for (int cycle = 0; cycle < 4; ++cycle) {
        ap->clk = !ap->clk;
        bp->clk = !bp->clk;
        ap->eval();
        bp->eval();
        contextp->timeInc(1);
        TEST_CHECK_EQ(static_cast<int>(ap->dflt_o), 9);
        TEST_CHECK_EQ(static_cast<int>(ap->set_o), 5);
        TEST_CHECK_EQ(static_cast<int>(bp->dflt_o), 9);
        TEST_CHECK_EQ(static_cast<int>(bp->set_o), 9);
        TEST_CHECK_EQ(static_cast<int>(ap->arr_dflt_o), 6);
        TEST_CHECK_EQ(static_cast<int>(ap->arr_set_o), 12);
        TEST_CHECK_EQ(static_cast<int>(bp->arr_set_o), 6);
        TEST_CHECK_EQ(static_cast<int>(ap->x_o), 0x45);
        TEST_CHECK_EQ(static_cast<int>(ap->other_o), 0x12 + 3 + 6);
        TEST_CHECK_EQ(static_cast<int>(ap->z_o), 0x85);
        TEST_CHECK_EQ(static_cast<int>(bp->z_o), 0x88);
    }
    ap->final();
    bp->final();
    if (!errors) printf("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
