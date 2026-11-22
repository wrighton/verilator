// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilated.h"
#include "verilated_vpi.h"

#include "TestCheck.h"

#include <memory>
#include VM_PREFIX_INCLUDE
#include VM_PREFIX_ROOT_INCLUDE

int errors = 0;
static VM_PREFIX* s_topp = nullptr;
static int s_counts[5] = {};
static int s_hostBias = 0;

extern "C" int count(int which, int value) {
    ++s_counts[which];
    return value;
}
extern "C" int add_host_bias(int value) { return value + s_hostBias; }
extern "C" void choose_format(svBit use_b);
static int s_deferCalls = 0;
extern "C" void cxx_defer_call(int value) { s_deferCalls += value; }
extern "C" void cxx_put_dpi(int value) { s_topp->rootp->t__DOT__pubDpi = value; }
extern "C" void cxx_put_ico(int value) { s_topp->rootp->t__DOT__pubIco = value; }
extern "C" void cxx_restore_stale() { s_topp->rootp->t__DOT__pubStale = 0; }
extern "C" void cxx_put_mix(int value) { s_topp->rootp->t__DOT__pubMix = value; }
extern "C" void cxx_put_last(int value) { s_topp->rootp->t__DOT__pubLast = value; }

// Evaluate, checking which readers ran and the outputs
static void evalCheck(bool inRuns, bool pubRuns) {
    int prev[5];
    for (int i = 0; i < 5; ++i) prev[i] = s_counts[i];
    s_hostBias += 10;
    s_topp->eval();
    TEST_CHECK_EQ(s_counts[0] - prev[0], inRuns || TEST_IN_EVERY);
    TEST_CHECK_EQ(s_counts[1] - prev[1], pubRuns || !TEST_PUB_DETECT);
    TEST_CHECK_EQ(s_counts[2] - prev[2], inRuns || !TEST_PUB_DETECT);
    TEST_CHECK_EQ(s_counts[3] - prev[3], 1);
    TEST_CHECK_EQ(s_counts[4] - prev[4], 1);
    auto* const rootp = s_topp->rootp;
    TEST_CHECK_EQ(s_topp->obsIn, s_topp->in * 3 + 1);
    TEST_CHECK_EQ(s_topp->obsPub, rootp->t__DOT__pub * 3 + 1);
    TEST_CHECK_EQ(s_topp->obsPub2, rootp->t__DOT__pub + 2);
    TEST_CHECK_EQ(s_topp->obsPubIn, s_topp->pubIn + 1);
    TEST_CHECK_EQ(s_topp->obsComb, (s_topp->in + 3) * 3 + 1);
    TEST_CHECK_EQ(s_topp->obsOut, (s_topp->in + 7) * 2);
    TEST_CHECK_EQ(s_topp->obsWr, rootp->t__DOT__pubWr * 2);
    TEST_CHECK_EQ(s_topp->obsWide[2], ~rootp->t__DOT__pubWide[2] & 0x7fffffff);
    TEST_CHECK_EQ(s_topp->obsStruct[1], rootp->t__DOT__pubStruct[1] + (1 << 22));
    TEST_CHECK_EQ(s_topp->obsBias, rootp->t__DOT__pubBias + s_hostBias);
    TEST_CHECK_EQ(s_topp->obsBias2, 3 * rootp->t__DOT__pubBias2 + 4 + 2 * s_hostBias);
    TEST_CHECK_EQ(s_topp->obsTime, s_topp->contextp()->time() > 100 ? rootp->t__DOT__pubTime : 0);
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    s_topp = topp.get();
    auto* const rootp = topp->rootp;

    topp->clk = 0;
    topp->in = 1;
    topp->inIco = 1;
    topp->inPlusArg = 1;
    topp->eval();
    TEST_CHECK_EQ(topp->obsEvent, 1);
    evalCheck(false, false);
    // A top level input, and a public variable written by the C++ model and by the VPI
    topp->in = 2;
    topp->inIco = 2;
    topp->pubIn = 2;
    evalCheck(true, false);
    TEST_CHECK_EQ(topp->obsIco, 3 * 2 * 2 + 1);
    rootp->t__DOT__pub = 5;
    evalCheck(false, true);
    const vpiHandle h = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.t.pub"), nullptr);
    TEST_CHECK_NZ(h);
    s_vpi_value v;
    v.format = vpiIntVal;
    v.value.integer = 7;
    vpi_put_value(h, &v, nullptr, vpiNoDelay);
    vpi_release_handle(h);
    evalCheck(false, true);
    // Writing the same value
    rootp->t__DOT__pub = 7;
    evalCheck(false, false);
    // Written and restored before the evaluation
    rootp->t__DOT__pub = 8;
    rootp->t__DOT__pub = 7;
    evalCheck(false, false);
    // Wide values
    rootp->t__DOT__pubWide[2] = 0x5;
    rootp->t__DOT__pubStruct[1] = 0x12345;
    evalCheck(false, false);

    int printedBase = 0;
    for (int i = 0; i < 4; ++i) {
        contextp->timeInc(1);
        topp->clk = 1;
        evalCheck(false, false);
        TEST_CHECK_EQ(topp->obsFlag, 4);
        // Clear the flag the design set in this evaluation
        rootp->t__DOT__flag = 0;
        evalCheck(false, false);
        TEST_CHECK_EQ(topp->obsFlag, 1);
        TEST_CHECK_EQ(topp->obsHidden, rootp->t__DOT__pubHidden * 3 + 1);
        TEST_CHECK_EQ(topp->obsDpi, rootp->t__DOT__pubDpi * 3 + 1);
        if (i == 0) {
            TEST_CHECK_EQ(rootp->t__DOT__pubStale, 0);
            // Documented limitation of change detection: the reader is not evaluated again
            TEST_CHECK_EQ(topp->obsStale, TEST_PUB_DETECT ? 4 : 1);
        }
        contextp->timeInc(1);
        topp->clk = 0;
        evalCheck(false, false);
        TEST_CHECK_EQ(topp->obsObj, topp->obsCyc);
        TEST_CHECK_EQ(topp->obsStatic, topp->obsCyc);
        // The formatted object grows by a character in each cycle
        if (i == 0) printedBase = topp->obsPrinted - topp->obsCyc;
        // Cleared after the time slot the event was triggered in
        TEST_CHECK_EQ(topp->obsEvent, 0);
        TEST_CHECK_EQ(topp->obsPrinted - topp->obsCyc, printedBase);
    }
    TEST_CHECK_EQ(rootp->t__DOT__pubDpi, 3);
    // A real value that compares equal to the previous one
    rootp->t__DOT__pubReal = -0.0;
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsReal, 1ULL << 63);
    // Written by C++ during the input combinational logic, which also writes it, but only when
    // its input changed
    topp->kick = 1;
    evalCheck(false, false);
    evalCheck(false, false);
    if (!TEST_IN_EVERY) {
        TEST_CHECK_EQ(rootp->t__DOT__pubMix, 23);
        // Documented limitation of change detection: the reader is not evaluated again
        TEST_CHECK_EQ(topp->obsMix, TEST_PUB_DETECT ? (topp->in + 5) * 3 + 1 : 23 * 3 + 1);
    }

    // Written by C++ during the input combinational logic, then by the design, then restored by
    // C++, all in one evaluation
    contextp->timeInc(1);
    topp->clk = 1;
    topp->kick2 = 1;
    evalCheck(false, false);
    contextp->timeInc(1);
    topp->clk = 0;
    evalCheck(false, false);
    TEST_CHECK_EQ(rootp->t__DOT__pubLast, 2);
    TEST_CHECK_EQ(topp->obsLast, 2 * 3 + 1);

    // The time passing the reader's threshold
    contextp->timeInc(200);
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsTime, 5);

    // Pushed to the queue in each evaluation
    const int pushed = topp->obsPushed;
    for (int i = 0; i < 3; ++i) evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsPushed, pushed + 6);

    // A new random number in each evaluation, and the command line extended
    const uint32_t drawn = topp->obsRand;
    const uint32_t drawnRange = topp->obsRandRange;
    const int dist = topp->obsDist;
    evalCheck(false, false);
    TEST_CHECK_NE(topp->obsRand, drawn);
    TEST_CHECK_NE(topp->obsRandRange, drawnRange);
    TEST_CHECK_EQ(topp->obsDist, dist);
    TEST_CHECK_EQ(topp->obsPlusArg, 3);
    TEST_CHECK_EQ(topp->obsPlusValue, 0);
    TEST_CHECK_EQ(topp->obsInPlusArg, 3);
    TEST_CHECK_EQ(topp->obsSeed, static_cast<int>(contextp->randSeed()));
    const char* addedArgs[] = {"+late_feature", "+late_value=42", "+late_input"};
    contextp->commandArgsAdd(3, addedArgs);
    evalCheck(false, false);
    // Input change detection alone does not see the command line
    TEST_CHECK_EQ(topp->obsInPlusArg, TEST_IN_EVERY || TEST_PUB_DETECT ? 17 : 3);
    TEST_CHECK_EQ(topp->obsPlusArg, 17);
    TEST_CHECK_EQ(topp->obsPlusValue, 42);

    // The time format changed, and written to the file in two evaluations, checked by the driver
    const svScope scope = svGetScopeFromName("top.t");
    TEST_CHECK_NZ(scope);
    const svScope oldScope = svSetScope(scope);
    choose_format(0);
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsStamp, 'A');
    choose_format(1);
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsStamp, 'B');
    svSetScope(oldScope);
    TEST_CHECK_EQ(topp->obsFormat, 3);
    rootp->t__DOT__pubFormat = 12;
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsFormat, 4);
    rootp->t__DOT__pubFile = 'X';
    evalCheck(false, false);
    evalCheck(false, false);
    rootp->t__DOT__pubFile = 0;
    evalCheck(false, false);

    // The assertions turned off, their inputs changed, then turned on
    TEST_CHECK_EQ(topp->obsForceAction, 5);
    contextp->assertOn(false);
    rootp->t__DOT__udefer__DOT__p = 1;
    rootp->t__DOT__uforce__DOT__gate = 0;
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsAssert, 0);
    TEST_CHECK_EQ(topp->obsDeferAction, 0);
    TEST_CHECK_EQ(topp->obsForceAction, 5);
    contextp->assertOn(true);
    evalCheck(false, false);
    TEST_CHECK_EQ(topp->obsAssert, 1);
    TEST_CHECK_EQ(topp->obsDeferAction, 1);
    TEST_CHECK_EQ(topp->obsForceAction, 1);

    // A deferred assertion failing in two time steps, written to the file by the driver
    rootp->t__DOT__ufile__DOT__p = 1;
    contextp->timeInc(1);
    evalCheck(false, false);
    contextp->timeInc(1);
    evalCheck(false, false);
    rootp->t__DOT__ufile__DOT__p = 0;
    evalCheck(false, false);

    // A deferred assertion calling C++ code, failing in two time steps
    rootp->t__DOT__ucall__DOT__p = 1;
    contextp->timeInc(1);
    evalCheck(false, false);
    contextp->timeInc(1);
    evalCheck(false, false);
    TEST_CHECK_EQ(s_deferCalls, 2);
    rootp->t__DOT__ucall__DOT__p = 0;
    evalCheck(false, false);

    // Assertions failing for two evaluations in each of two time steps, counted by the driver
    rootp->t__DOT__pubOneHot = 3;
    rootp->t__DOT__pubOneHotImm = 3;
    rootp->t__DOT__pubOneHotNoTime = 3;
    for (int step = 0; step < 2; ++step) {
        contextp->timeInc(1);
        evalCheck(false, false);
        evalCheck(false, false);
    }
    rootp->t__DOT__pubOneHot = 1;
    rootp->t__DOT__pubOneHotImm = 1;
    rootp->t__DOT__pubOneHotNoTime = 1;
    evalCheck(false, false);

    // The latch enabled, then evaluated with no change
    rootp->t__DOT__ulatch__DOT__rst = 0;
    rootp->t__DOT__ulatch__DOT__p = 1;
    topp->eval();
    const int latched = topp->obsLatch;
    topp->eval();
    // Documented: with change detection, the latch runs only when an input changed, as IEEE
    // specifies, rather than in each evaluation
    TEST_CHECK_EQ(topp->obsLatch - latched, TEST_PUB_DETECT ? 0 : 1);

    // A deferred assertion failing while turned off, then turned on with the same input and time
    contextp->fatalOnError(false);
    contextp->assertOn(false);
    rootp->t__DOT__ufatal__DOT__p = 1;
    topp->eval();
    contextp->assertOn(true);
    topp->eval();
    // Documented: with change detection, the change of the assertion controls takes effect for an
    // assertion with only reports, including ending the simulation, when its logic next runs
    TEST_CHECK_EQ(contextp->gotFinish(), !TEST_PUB_DETECT);
    TEST_CHECK_EQ(contextp->gotError(), !TEST_PUB_DETECT);

    topp->final();
    return errors ? 10 : 0;
}
