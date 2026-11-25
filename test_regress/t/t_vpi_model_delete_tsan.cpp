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

#include <atomic>
#include <memory>
#include <thread>

int errors = 0;

static int s_valueCbCalls = 0;

static PLI_INT32 valueCb(p_cb_data) {
    ++s_valueCbCalls;
    return 0;
}

static vpiHandle registerValueCb(vpiHandle objp) {
    static s_vpi_time cbTime{vpiSuppressTime, 0, 0, 0.0};
    static s_vpi_value cbValue{vpiIntVal, {0}};
    s_cb_data cbData{};
    cbData.reason = cbValueChange;
    cbData.cb_rtn = valueCb;
    cbData.obj = objp;
    cbData.time = &cbTime;
    cbData.value = &cbValue;
    return vpi_register_cb(&cbData);
}

static void tick(VM_PREFIX* topp) {
    topp->clk = !topp->clk;
    topp->eval();
    VerilatedVpi::callValueCbs();
    VerilatedVpi::doInertialPuts();
}

int main(int argc, char** argv) {
    // A model whose VPI callbacks and delayed puts are all gone may be deleted on another
    // thread, while the main thread keeps using the VPI on another model
    const std::unique_ptr<VerilatedContext> contextAp{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> topAp{new VM_PREFIX{contextAp.get(), "a"}};
    const vpiHandle cntAp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("a.t.cnt"), nullptr);
    TEST_CHECK_NZ(cntAp);
    for (int i = 0; i < 20; ++i) {
        VerilatedContext* const contextBp = new VerilatedContext;
        VM_PREFIX* const topBp = new VM_PREFIX{contextBp, "b"};
        const vpiHandle cntBp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("b.t.cnt"), nullptr);
        TEST_CHECK_NZ(cntBp);
        vpi_remove_cb(registerValueCb(cntBp));
        s_vpi_value putValue{vpiIntVal, {0}};
        s_vpi_time putTime{vpiSimTime, 0, 1, 0.0};
        vpi_put_value(cntBp, &putValue, &putTime, vpiInertialDelay);
        vpi_release_handle(cntBp);
        tick(topBp);
        std::atomic<bool> done{false};
        std::thread deleter{[&] {
            delete topBp;
            delete contextBp;
            done = true;
        }};
        while (!done) {
            const vpiHandle cbp = registerValueCb(cntAp);
            tick(topAp.get());
            vpi_remove_cb(cbp);
        }
        deleter.join();
        Verilated::threadContextp(contextAp.get());
    }
    TEST_CHECK_NE(s_valueCbCalls, 0);
    vpi_release_handle(cntAp);
    topAp->final();
    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
