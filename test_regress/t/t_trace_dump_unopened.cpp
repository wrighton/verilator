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
    contextp->traceEverOn(true);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    // Dumping a trace that was never traced nor opened does nothing
    VerilatedVcdC unopened;
    unopened.dump(1);
    if (unopened.isOpen()) vl_fatal(__FILE__, __LINE__, "main", "Trace is open");

    // Nor does dumping a trace that failed to open
    VerilatedVcdC failed;
    topp->trace(&failed, 99);
    failed.open(VL_STRINGIFY(TEST_OBJ_DIR) "/no_such_dir/simx.vcd");
    failed.dump(1);
    if (failed.isOpen()) vl_fatal(__FILE__, __LINE__, "main", "Trace is open");

    topp->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
