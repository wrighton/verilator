// DESCRIPTION: Query per-assertion control state from C++ with a run-time query.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
#include VM_PREFIX_INCLUDE

#include <array>
#include <cstdio>
#include <cstdlib>
#include <memory>

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
int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->threads(1);
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get()}};
    topp->eval();
    {
        VlAssertControl state;
        state.configure(contextp.get(), 8);  // Simple immediate assert
        for (uint32_t effect : {3U, 6U, 8U}) contextp->assertCtl(effect, 2, 1, state);
        require(observe(state) == std::array<uint32_t, 5>{{1, 0, 1, 1, 1}},
                "On/PassOn/FailOn state failed");
        for (uint32_t effect : {11U, 5U}) contextp->assertCtl(effect, 2, 1, state);
        require(observe(state) == std::array<uint32_t, 5>{{0, 1, 0, 1, 1}},
                "VacuousOff/Kill state failed");
    }
    topp->final();
    std::puts("*-* All Finished *-*");
    return 0;
}
