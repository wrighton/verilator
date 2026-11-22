// DESCRIPTION: Assertion state serialization and live destination registration.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#include VM_PREFIX_INCLUDE
#include "verilated_save.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "%s\n", message);
        std::exit(1);
    }
}
static void pulse(VM_PREFIX& model) {
    model.clk = 0;
    model.eval();
    model.clk = 1;
    model.eval();
}
static std::array<uint32_t, 5> queries(const VlAssertControl& state) {
    return {state.get(VerilatedAssertCtlQuery::ASSERT_CTL_ON),
            state.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL),
            state.get(VerilatedAssertCtlQuery::ASSERT_CTL_PASS_ON_VACUOUS),
            state.get(VerilatedAssertCtlQuery::ASSERT_CTL_PASS_ON_NONVACUOUS),
            state.get(VerilatedAssertCtlQuery::ASSERT_CTL_FAIL_ON)};
}
int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> sourcep{new VerilatedContext};
    sourcep->threads(1);
    sourcep->commandArgs(argc, argv);
    VM_PREFIX source{sourcep.get()};
    source.clk = 0;
    source.eval();
    pulse(source);
    require(source.afails == 0 && source.bfails == 1, "Initial scoped OFF/Lock failed");

    VlAssertControl sourceState;
    sourceState.configure(sourcep.get(), 8);
    VlAssertCtlTable table;
    const auto bind
        = [&](std::vector<VlAssertCtlTable::Target>& targets) { targets = {{&sourceState, 0}}; };
    for (uint32_t effect : {6U, 11U, 9U, 5U, 1U})
        sourcep->assertCtlTable(effect, 2, 1, 1, table, bind);
    const auto expected = queries(sourceState);
    require(expected == std::array<uint32_t, 5>{{0, 1, 0, 1, 0}},
            "Source action/Kill state failed");
    const std::string filename = std::string{VL_STRINGIFY(TEST_OBJ_DIR)} + "/saved.vltsv";
    VerilatedSave output;
    output.open(filename);
    require(output.isOpen(), "Save open failed");
    output << source << sourceState;
    output.close();

    const std::unique_ptr<VerilatedContext> destinationp{new VerilatedContext};
    destinationp->threads(1);
    VM_PREFIX destination{destinationp.get()};
    VlAssertControl destinationState;
    destinationState.configure(destinationp.get(), 8);
    require(queries(destinationState) != expected, "Destination did not start independently");
    VerilatedRestore input;
    input.open(filename);
    require(input.isOpen(), "Restore open failed");
    input >> destination >> destinationState;
    input.close();
    require(queries(destinationState) == expected, "Restored flags/actions/Kill differ");
    destinationp->assertCtl(3, 2, 1);
    require(!destinationState.get(VerilatedAssertCtlQuery::ASSERT_CTL_ON),
            "Restored Lock was lost");
    pulse(destination);
    require(destination.afails == 0 && destination.bfails == 2,
            "Restored model OFF/Lock/failure state failed");
    destinationp->assertCtl(4, 2, 1);
    pulse(destination);
    require(destination.afails == 0 && destination.bfails == 2,
            "Restored model registry lost global OFF");
    destinationp->assertCtl(2, 2, 1);
    destinationp->assertCtl(3, 2, 1);
    require(destinationState.get(VerilatedAssertCtlQuery::ASSERT_CTL_ON),
            "Destination registry or known mask lost");
    pulse(destination);
    require(destination.afails == 1 && destination.bfails == 3,
            "Restored model Unlock/ON actions failed");
    require(queries(sourceState) == expected, "Destination control affected source context");
    source.final();
    destination.final();
    std::puts("*-* All Finished *-*");
}
