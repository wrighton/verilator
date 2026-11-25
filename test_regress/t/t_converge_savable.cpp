//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0
//

#include <verilated.h>
#include <verilated_save.h>

#include <memory>

#include VM_PREFIX_INCLUDE

// These require the above. Comment prevents clang-format moving them
#include "TestCheck.h"

int errors = 0;

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    const char* const filenamep = VL_STRINGIFY(TEST_OBJ_DIR) "/saved.vltsv";
    if (contextp->commandArgsPlusMatch("save")[0]) {
        topp->cap = 0;
        topp->eval();
        VerilatedSave os;
        os.open(filenamep);
        os << *topp;
        os.close();
        return 0;
    }
    VerilatedRestore is;
    is.open(filenamep);
    is >> *topp;
    is.close();
    // Takes more iterations than --converge-limit allows
    topp->cap = 500;
    topp->eval();
    TEST_CHECK_EQ(topp->q, 500);
    topp->final();
    return errors ? 10 : 0;
}
