// DESCRIPTION: Assertion state serialization and live destination registration.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#include VM_PREFIX_INCLUDE
#include "verilated_save.h"

#include <array>
#include <cstdio>
#include <cstdlib>
#include <initializer_list>
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
enum Effect : uint32_t {
    Lock = 1,
    Unlock = 2,
    On = 3,
    Off = 4,
    Kill = 5,
    PassOn = 6,
    PassOff = 7,
    FailOn = 8,
    FailOff = 9,
    NonvacuousOn = 10,
    VacuousOff = 11,
};

static void scoped(VerilatedContext& context, VlAssertControl& state,
                   std::initializer_list<Effect> effects) {
    VlAssertCtlTable table;
    const auto bind
        = [&](std::vector<VlAssertCtlTable::Target>& targets) { targets = {{&state, 0}}; };
    for (Effect effect : effects) context.assertCtlTable(effect, 2, 1, 1, table, bind);
}

static void testSharedFields(const std::string& filename) {
    VerilatedContext saved;
    for (int i = 0; i < 4; ++i) saved.assertCtl(Kill, 2, 1);
    saved.assertCtl(PassOff, 2, 1);
    saved.assertCtl(FailOff, 2, 1);
    saved.assertCtl(Lock, 2, 1);

    VerilatedContext live;
    VlAssertControl inherited, partial, killed, locked;
    for (VlAssertControl* statep : {&inherited, &partial, &killed, &locked}) {
        statep->configure(&live, 8);
    }
    scoped(live, locked, {Lock});
    live.assertCtl(NonvacuousOn, 2, 1);  // No change to the context or the locked site.
    scoped(live, killed, {Kill, Kill, FailOn});
    live.assertCtl(FailOn, 2, 1);  // The accepted global write supersedes scoped FailOn.
    live.assertCtl(Kill, 2, 1);
    require(queries(killed)[1] == 3, "Global Kill did not advance the scoped generation");
    scoped(live, partial, {NonvacuousOn, FailOn, Unlock});  // Explicit no-op writes.

    VerilatedSave output;
    output.open(filename);
    require(output.isOpen(), "Context save open failed");
    output << partial << &saved << &saved;
    saved.assertOn(true);
    output << &saved;
    output.close();
    scoped(live, partial, {PassOff, FailOff, Lock});

    VerilatedRestore input;
    input.open(filename);
    require(input.isOpen(), "Context restore open failed");
    input >> partial >> &live;
    require(queries(inherited) == std::array<uint32_t, 5>{{0, 4, 0, 0, 0}},
            "Restored defaults did not reach an inherited site");
    require(queries(partial) == std::array<uint32_t, 5>{{0, 4, 0, 1, 1}},
            "Saved no-op overrides or independent pass fields were lost");
    require(queries(killed) == std::array<uint32_t, 5>{{0, 3, 0, 0, 0}},
            "Shared Kill erased a scoped generation or global FailOn retained ownership");
    require(queries(locked) == std::array<uint32_t, 5>{{1, 0, 0, 0, 0}},
            "A default-only Kill or no-op assignment affected a locally locked site");

    scoped(live, inherited, {On});
    scoped(live, partial, {On});
    require(!queries(inherited)[0] && queries(partial)[0],
            "Restored default Lock or saved scoped Unlock was lost");
    live.assertCtl(Kill, 2, 1);  // Locked defaults reject Kill but the unlocked site accepts it.
    live.assertOn(true);
    input >> &live;
    require(queries(partial) == std::array<uint32_t, 5>{{0, 5, 0, 1, 1}},
            "C++ assertOn retained ON ownership or cleared unrelated overrides");

    live.assertOn(true);
    scoped(live, partial, {Off});
    const char* argv[] = {"test", "+verilator+assert+lock", "+verilator+noassert"};
    live.commandArgs(3, argv);
    require(!queries(inherited)[0], "noassert did not force off with assertion controls locked");
    input >> &live;
    input.close();
    require(queries(partial) == std::array<uint32_t, 5>{{1, 5, 0, 1, 1}},
            "noassert retained ON ownership or cleared unrelated overrides");
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> sourcep{new VerilatedContext};
    sourcep->threads(1);
    sourcep->commandArgs(argc, argv);
    VM_PREFIX source{sourcep.get()};
    source.scoped_off = 1;
    source.clk = 0;
    source.eval();
    pulse(source);
    require(source.afails == 0 && source.bfails == 1, "Initial scoped OFF/Lock failed");

    VlAssertControl sourceState;
    sourceState.configure(sourcep.get(), 8);
    scoped(*sourcep, sourceState, {PassOn, VacuousOff, FailOff, Kill, Lock});
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
    VM_PREFIX destination{destinationp.get(), "destination"};
    VlAssertControl destinationState;
    destinationState.configure(destinationp.get(), 8);
    require(queries(destinationState) != expected, "Destination did not start independently");

    // Restore into one model without replacing the state of its running peers.
    destinationp->assertOn(false);
    VM_PREFIX inheritedPeer{destinationp.get(), "inheritedPeer"};
    VM_PREFIX scopedPeer{destinationp.get(), "scopedPeer"};
    inheritedPeer.scoped_off = 0;
    scopedPeer.scoped_off = 1;  // Explicitly disable a when it is already off.
    pulse(inheritedPeer);
    pulse(scopedPeer);
    require(inheritedPeer.afails == 0 && inheritedPeer.bfails == 0,
            "Peer did not start with assertions disabled");
    require(scopedPeer.afails == 0 && scopedPeer.bfails == 0,
            "Scoped peer did not start with assertions disabled");

    VerilatedRestore input;
    input.open(filename);
    require(input.isOpen(), "Restore open failed");
    input >> destination >> destinationState;
    input.close();
    pulse(inheritedPeer);
    pulse(scopedPeer);
    require(inheritedPeer.afails == 1 && inheritedPeer.bfails == 1,
            "Live peer did not inherit restored ON for both assertions");
    require(scopedPeer.afails == 0 && scopedPeer.bfails == 1,
            "Live peer lost its explicit scoped OFF override");
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
    inheritedPeer.final();
    scopedPeer.final();
    testSharedFields(filename + ".ctx");
    std::puts("*-* All Finished *-*");
}
