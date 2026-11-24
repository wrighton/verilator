// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"

#include <memory>

#include VM_PREFIX_INCLUDE
#include "Vt_trace_two_b.h"
#include "Vt_trace_two_b__ALL.cpp"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->debug(0);
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true);
    // Model 'a' dumps all models in the context, including 'b'
    const std::unique_ptr<VM_PREFIX> ap{new VM_PREFIX{contextp.get(), "topa"}};
    std::unique_ptr<Vt_trace_two_b> bp{new Vt_trace_two_b{contextp.get(), "topb"}};

    ap->clk = false;
    contextp->timeInc(10);
    while (contextp->time() < 1100 && !contextp->gotFinish()) {
        // 'b' is deleted while 'a' keeps running and dumping
        if (bp && contextp->time() > 60) bp.reset();
        ap->clk = !ap->clk;
        if (bp) bp->clk = ap->clk;
        ap->eval_step();
        if (bp) bp->eval_step();
        ap->eval_end_step();
        if (bp) bp->eval_end_step();
        contextp->timeInc(5);
    }
    if (!contextp->gotFinish()) {
        vl_fatal(__FILE__, __LINE__, "main", "%Error: Timeout; never got a $finish");
    }
    ap->final();
    return 0;
}
