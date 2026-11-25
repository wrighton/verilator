// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>
#include <verilated_vcd_c.h>

#include <memory>

#include VM_PREFIX_INCLUDE

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->debug(0);
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);

    const std::unique_ptr<VM_PREFIX> top{new VM_PREFIX{contextp.get(), "top"}};
    const std::unique_ptr<VerilatedVcdC> tfp{new VerilatedVcdC};
    top->trace(tfp.get(), 99);
    tfp->rolloverSize(1000);  // But will be increased to 8kb chunk size

    // Each dumps 'cycles' cycles to a new rollover sequence
    const auto dumpTo = [&](const char* filenamep, uint64_t cycles) {
        tfp->open(filenamep);
        for (const uint64_t end = contextp->time() + cycles; contextp->time() < end;
             contextp->timeInc(1)) {
            top->clk = !top->clk;
            top->eval();
            tfp->dump(contextp->time());
        }
        tfp->close();
    };

    // No extension
    dumpTo(VL_STRINGIFY(TEST_OBJ_DIR) "/simnodot", 1900);
    // No extension, a dot in a directory name
    Verilated::mkdir(VL_STRINGIFY(TEST_OBJ_DIR) "/dir.x");
    dumpTo(VL_STRINGIFY(TEST_OBJ_DIR) "/dir.x/sim", 1900);
    // Numbered past _cat9999
    dumpTo(VL_STRINGIFY(TEST_OBJ_DIR) "/simwrap_cat9998.vcd", 3800);

    top->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
