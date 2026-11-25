// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>
#include <verilated_fst_c.h>
#include <verilated_saif_c.h>
#include <verilated_vcd_c.h>

#include <memory>

#include VM_PREFIX_INCLUDE

// Trace objects with static storage duration, destroyed after main returns
static VerilatedVcdC s_vcd;
static VerilatedFstC s_fst;
static VerilatedSaifC s_saif;

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    topp->trace(&s_vcd, 99);
    topp->trace(&s_fst, 99);
    topp->trace(&s_saif, 99);
    s_vcd.open(VL_STRINGIFY(TEST_OBJ_DIR) "/simx.vcd");
    s_fst.open(VL_STRINGIFY(TEST_OBJ_DIR) "/simx.fst");
    s_saif.open(VL_STRINGIFY(TEST_OBJ_DIR) "/simx.saif");
    for (int i = 0; i < 10; ++i) {
        topp->clk = !topp->clk;
        topp->eval();
        s_vcd.dump(contextp->time());
        s_fst.dump(contextp->time());
        s_saif.dump(contextp->time());
        contextp->timeInc(5);
    }
    topp->final();
    s_vcd.close();
    s_fst.close();
    s_saif.close();
    printf("*-* All Finished *-*\n");
    return 0;
}
