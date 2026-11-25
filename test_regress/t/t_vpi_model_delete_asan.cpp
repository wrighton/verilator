// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#include "verilated.h"
#include "verilated_vpi.h"

#include "TestCheck.h"
#include VM_PREFIX_INCLUDE

#include <memory>

int errors = 0;

static int s_valueCbCalls = 0;

static PLI_INT32 valueCb(p_cb_data) {
    ++s_valueCbCalls;
    return 0;
}

// A model owned by static objects, destroyed at exit
std::unique_ptr<VerilatedContext> g_contextp;
std::unique_ptr<VM_PREFIX> g_topp;

// Run a model for some cycles, servicing VPI callbacks and puts as a harness does
static void runModel(std::unique_ptr<VerilatedContext>& contextp, std::unique_ptr<VM_PREFIX>& topp,
                     bool leaveVpiWork) {
    contextp.reset(new VerilatedContext);
    topp.reset(new VM_PREFIX{contextp.get(), ""});
    const vpiHandle cntp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.cnt"), nullptr);
    TEST_CHECK_NZ(cntp);
    if (leaveVpiWork) {
        // A value change callback left registered when the model is deleted
        s_vpi_time cbTime{vpiSuppressTime, 0, 0, 0.0};
        s_vpi_value cbValue{vpiIntVal, {0}};
        s_cb_data cbData{};
        cbData.reason = cbValueChange;
        cbData.cb_rtn = valueCb;
        cbData.obj = cntp;
        cbData.time = &cbTime;
        cbData.value = &cbValue;
        const vpiHandle cbp = vpi_register_cb(&cbData);
        TEST_CHECK_NZ(cbp);
        vpi_release_handle(cbp);  // Releasing the handle keeps the callback
    }
    for (int i = 0; i < 20; ++i) {
        topp->clk = !topp->clk;
        topp->eval();
        VerilatedVpi::callValueCbs();
        VerilatedVpi::doInertialPuts();
        contextp->timeInc(1);
    }
    if (leaveVpiWork) {
        // A delayed put left pending when the model is deleted
        s_vpi_value putValue{vpiIntVal, {0}};
        putValue.value.integer = 42;
        s_vpi_time putTime{vpiSimTime, 0, 1, 0.0};
        vpi_put_value(cntp, &putValue, &putTime, vpiInertialDelay);
    }
    vpi_release_handle(cntp);
    topp->final();
}

// A model deleted by its own value change callback
std::unique_ptr<VerilatedContext> g_selfContextp;
std::unique_ptr<VM_PREFIX> g_selfTopp;

static PLI_INT32 deleteModelCb(p_cb_data) {
    g_selfTopp.reset();
    return 0;
}

static void runSelfDeletingModel() {
    g_selfContextp.reset(new VerilatedContext);
    g_selfTopp.reset(new VM_PREFIX{g_selfContextp.get(), ""});
    g_selfTopp->clk = 0;
    g_selfTopp->eval();
    const vpiHandle cntp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.cnt"), nullptr);
    TEST_CHECK_NZ(cntp);
    s_vpi_time cbTime{vpiSuppressTime, 0, 0, 0.0};
    s_vpi_value cbValue{vpiIntVal, {0}};
    s_cb_data cbData{};
    cbData.reason = cbValueChange;
    cbData.cb_rtn = deleteModelCb;
    cbData.obj = cntp;
    cbData.time = &cbTime;
    cbData.value = &cbValue;
    vpi_release_handle(vpi_register_cb(&cbData));
    vpi_release_handle(cntp);
    g_selfTopp->clk = 1;
    g_selfTopp->eval();
    VerilatedVpi::callValueCbs();
    TEST_CHECK_Z(g_selfTopp.get());
    g_selfContextp.reset();
}

static void runLocalModel(bool leaveVpiWork) {
    std::unique_ptr<VerilatedContext> contextp;
    std::unique_ptr<VM_PREFIX> topp;
    runModel(contextp, topp, leaveVpiWork);
}

int main(int argc, char** argv) {
    // The callbacks and puts left on a deleted model are not called or applied by another model
    runLocalModel(true);
    TEST_CHECK_EQ(s_valueCbCalls, 10);
    s_valueCbCalls = 0;
    runLocalModel(false);
    TEST_CHECK_EQ(s_valueCbCalls, 0);
    // A model may be deleted by one of its callbacks
    runSelfDeletingModel();
    runLocalModel(false);
    // Also when the model is destroyed at exit, with its callbacks and puts left
    runModel(g_contextp, g_topp, true);
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
