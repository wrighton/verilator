// DESCRIPTION: Global C++ and runtime controls over selected assertions.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#include VM_PREFIX_INCLUDE

#include <cstdio>
#include <cstdlib>
#include <memory>

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "%%Error: %s\n", message);
        std::exit(1);
    }
}
static void pulse(VM_PREFIX& model) {
    model.clk = 0;
    model.eval();
    model.clk = 1;
    model.eval();
}
int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->threads(1);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    topp->clk = 0;
    topp->eval();
    pulse(*topp);
    require(topp->afails == 0 && topp->bfails == 1, "Selected off/lock reached b");

    contextp->assertOn(false);
    pulse(*topp);
    require(topp->afails == 0 && topp->bfails == 1, "assertOn(false) did not stop b");

    // The C++ API overrides the On state regardless of a per-assertion Lock
    contextp->assertOn(true);
    pulse(*topp);
    require(topp->afails == 1 && topp->bfails == 2, "assertOn(true) did not restart a and b");

    // Parsed after the model registered its assertions
    const char* argsp[] = {"+verilator+noassert"};
    contextp->commandArgsAdd(1, argsp);
    pulse(*topp);
    require(topp->afails == 1 && topp->bfails == 2, "+verilator+noassert did not stop a and b");

    contextp->assertOn(true);
    pulse(*topp);
    require(topp->afails == 2 && topp->bfails == 3, "assertOn(true) after noassert failed");

    topp->final();
    std::puts("*-* All Finished *-*");
    return 0;
}
