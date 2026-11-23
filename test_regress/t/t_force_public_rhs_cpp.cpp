// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include "verilatedos.h"

#include "verilated.h"
#include "verilated_vpi.h"

#include <memory>

#include VM_PREFIX_INCLUDE
#include VM_PREFIX_ROOT_INCLUDE

static vpiHandle s_risesp = nullptr;
static int s_rises = 0;

static PLI_INT32 y_change_cb(p_cb_data cb_data) {
    if (cb_data->value->value.integer != 1) return 0;
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = ++s_rises;
    vpi_put_value(s_risesp, &val, nullptr, vpiNoDelay);
    return 0;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    topp->clk_in = 0;
    topp->eval();

    s_risesp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.t.vpi_rises"), nullptr);
    s_vpi_time t;
    t.type = vpiSuppressTime;
    s_vpi_value val;
    val.format = vpiIntVal;
    t_cb_data cb_data;
    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = y_change_cb;
    cb_data.obj = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.t.y"), nullptr);
    cb_data.time = &t;
    cb_data.value = &val;
    cb_data.user_data = nullptr;
    if (!s_risesp || !cb_data.obj) vl_fatal(__FILE__, __LINE__, "main", "Cannot find signals");
    vpi_register_cb(&cb_data);

    bool forced = false;
    while (!contextp->gotFinish()) {
        topp->eval();
        VerilatedVpi::callValueCbs();
        if (!forced && contextp->time() >= 3) {
            topp->rootp->t__DOT__x__VforceVal = 0xcc;
            topp->rootp->t__DOT__x__VforceEn = 0xff;
            topp->rootp->t__DOT__z__VforceVal = 0x3c;
            topp->rootp->t__DOT__z__VforceEn = 0xff;
            topp->rootp->t__DOT__w__VforceVal = 0x3c;
            topp->rootp->t__DOT__w__VforceEn = 0xff;
            topp->rootp->t__DOT__w__VforceVpi = 0xff;
            forced = true;
            topp->eval();
        }
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
    topp->final();
    return 0;
}
