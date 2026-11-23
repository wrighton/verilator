// DESCRIPTION: Context assertion controls applied before a model registers its assertions.
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
    // Before the model exists: its assertions take this state when they register
    constexpr VerilatedAssertType_t types = 0xff;
    constexpr VerilatedAssertDirectiveType_t directives = 7;
    contextp->assertCtl(7, types, directives);  // PassOff
    contextp->assertCtl(9, types, directives);  // FailOff
    contextp->assertCtl(4, types, directives);  // Off
    contextp->assertCtl(1, types, directives);  // Lock
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    // Instance b carries the checks: a's own code also turns off and locks a
    topp->clk = 0;
    topp->off_whole = 0;
    topp->eval();
    pulse(*topp);
    require(topp->bfails == 0, "Off and FailOff before construction not applied");

    contextp->assertCtl(3, types, directives);  // On, but locked
    contextp->assertCtl(8, types, directives);  // FailOn, but locked
    pulse(*topp);
    require(topp->bfails == 0, "Lock before construction not applied");

    contextp->assertCtl(2, types, directives);  // Unlock
    contextp->assertCtl(8, types, directives);  // FailOn, still Off
    pulse(*topp);
    require(topp->bfails == 0, "Off before construction not applied");

    contextp->assertCtl(3, types, directives);  // On
    pulse(*topp);
    require(topp->bfails == 1, "Unlock and On not applied");

    topp->final();
    std::puts("*-* All Finished *-*");
    return 0;
}
