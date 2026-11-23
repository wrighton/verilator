// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <string>

#include VM_PREFIX_INCLUDE

static uint64_t bitsOf(double value) {
    uint64_t result;
    std::memcpy(&result, &value, sizeof(result));
    return result;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    // Values that compare equal to the previous one but differ, and one that compares unequal to
    // itself, each also driven twice in a row
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double values[] = {0.0, -0.0, -0.0, 0.0, nan, nan, 1.5, nan, -nan, 2.5};
    for (const double value : values) {
        topp->r = value;
        topp->eval();
        if (topp->bits != bitsOf(value)) {
            const std::string msg = "%Error: incorrect output, got: " + std::to_string(topp->bits)
                                    + " expected: " + std::to_string(bitsOf(value));
            vl_fatal(__FILE__, __LINE__, "main", msg.c_str());
        }
    }

    topp->final();
    VL_PRINTF("*-* All Finished *-*\n");
    return 0;
}
