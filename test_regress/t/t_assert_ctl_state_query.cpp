// DESCRIPTION: Query per-assertion control state from C++ with a run-time query.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#include VM_PREFIX_INCLUDE

#include <array>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <thread>
#include <vector>

static void require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "%%Error: %s\n", message);
        std::exit(1);
    }
}
// One query site, reached with every query value at run time
static std::array<uint32_t, 5> observe(const VlAssertControl& state) {
    static constexpr std::array<VerilatedAssertCtlQuery, 5> queries{
        {VerilatedAssertCtlQuery::ASSERT_CTL_ON, VerilatedAssertCtlQuery::ASSERT_CTL_KILL,
         VerilatedAssertCtlQuery::ASSERT_CTL_PASS_ON_VACUOUS,
         VerilatedAssertCtlQuery::ASSERT_CTL_PASS_ON_NONVACUOUS,
         VerilatedAssertCtlQuery::ASSERT_CTL_FAIL_ON}};
    std::array<uint32_t, 5> result{};
    for (size_t i = 0; i < queries.size(); ++i) result[i] = state.get(queries[i]);
    return result;
}
static bool consistentConcurrentControl(VerilatedContext& context, const VlAssertControl& state) {
    constexpr unsigned rounds = 200000;
    std::atomic<unsigned> started{0};
    std::atomic<unsigned> finished{0};
    std::thread noassert([&]() {
        const char* argv[] = {"+verilator+noassert"};
        for (unsigned round = 1; round <= rounds; ++round) {
            while (started.load(std::memory_order_acquire) != round) std::this_thread::yield();
            context.commandArgsAdd(1, argv);
            finished.store(round, std::memory_order_release);
        }
    });
    bool consistent = true;
    for (unsigned round = 1; round <= rounds; ++round) {
        started.store(round, std::memory_order_release);
        context.assertOn(true);
        while (finished.load(std::memory_order_acquire) != round) std::this_thread::yield();
        // Both calls have finished; either order is legal, but the two paths must agree.
        const bool selected = state.get(VerilatedAssertCtlQuery::ASSERT_CTL_ON) != 0;
        if (selected != context.assertOn()) consistent = false;
    }
    noassert.join();
    return consistent;
}

static void checkMixedControl(VerilatedContext& context) {
    VlAssertControl first;
    VlAssertControl second;
    first.configure(&context, 8);
    second.configure(&context, 8);
    require(first.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL) == 0,
            "Mixed control starts with a nonzero Kill generation");
    VlAssertCtlTable shared;
    VlAssertCtlTable local;
    unsigned bindings = 0;
    const auto bindShared = [&](std::vector<VlAssertCtlTable::Target>& targets) {
        ++bindings;
        targets = {{&first, 2, 0}, {&second, 1, 1}};
    };
    const auto bindLocal
        = [&](std::vector<VlAssertCtlTable::Target>& targets, std::vector<uint32_t>& skipped) {
              ++bindings;
              targets = {{&first, 0, 0}};
              skipped = {0};
          };
    context.assertCtlMixedTable(5, 2, 1, 1, shared, bindShared, local, bindLocal);
    require(first.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL) == 1,
            "Mixed Kill missed a shallower local alias");
    require(second.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL) == 0,
            "Mixed Kill ignored the depth limit");
    context.assertCtlMixedTable(5, 2, 1, 3, shared, bindShared, local, bindLocal);
    require(first.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL) == 2,
            "Mixed Kill updated an aliased state twice");
    require(second.get(VerilatedAssertCtlQuery::ASSERT_CTL_KILL) == 1,
            "Mixed Kill missed a shared target");
    require(bindings == 2, "Mixed assertion control tables were not cached");
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->threads(1);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    topp->eval();
    checkMixedControl(*contextp);
    {
        VlAssertControl state;
        state.configure(contextp.get(), 8);  // Simple immediate assert
        VlAssertCtlTable table;
        unsigned bindings = 0;
        const auto bind = [&](std::vector<VlAssertCtlTable::Target>& targets) {
            ++bindings;
            targets.push_back({&state, 0});
        };
        for (uint32_t effect : {3U, 6U, 8U}) contextp->assertCtlTable(effect, 2, 1, 1, table, bind);
        require(observe(state) == std::array<uint32_t, 5>{{1, 0, 1, 1, 1}},
                "On/PassOn/FailOn state failed");
        for (uint32_t effect : {11U, 5U}) contextp->assertCtlTable(effect, 2, 1, 1, table, bind);
        require(observe(state) == std::array<uint32_t, 5>{{0, 1, 0, 1, 1}},
                "VacuousOff/Kill state failed");
        require(bindings == 1, "Assertion control table was not cached");
        require(consistentConcurrentControl(*contextp, state),
                "Concurrent noassert and assertOn left inconsistent assertion states");
    }
    topp->final();
    std::puts("*-* All Finished *-*");
    return 0;
}
