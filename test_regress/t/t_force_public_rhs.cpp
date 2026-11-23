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

#include "vpi_user.h"

// Count the value changes of the forced 't.y' and write the count to 't.vpi_changes', and
// force and release 't.w' while it is forced in code

static vpiHandle s_countp = nullptr;
static vpiHandle s_wp = nullptr;
static int s_changes = 0;

static PLI_INT32 w_action_cb(p_cb_data cb_data) {
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = 0;
    vpi_put_value(s_wp, &val, nullptr, cb_data->user_data ? vpiForceFlag : vpiReleaseFlag);
    return 0;
}

static void w_action_at(PLI_UINT32 time, bool force) {
    s_vpi_time t;
    t.type = vpiSimTime;
    t.high = 0;
    t.low = time;
    t_cb_data cb_data;
    cb_data.reason = cbAfterDelay;
    cb_data.cb_rtn = w_action_cb;
    cb_data.obj = nullptr;
    cb_data.time = &t;
    cb_data.value = nullptr;
    cb_data.user_data = force ? const_cast<PLI_BYTE8*>("force") : nullptr;
    vpi_register_cb(&cb_data);
}

static PLI_INT32 y_change_cb(p_cb_data /*cb_data*/) {
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = ++s_changes;
    vpi_put_value(s_countp, &val, nullptr, vpiNoDelay);
    return 0;
}

static PLI_INT32 start_of_sim_cb(p_cb_data /*cb_data*/) {
    vpiHandle const yp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.y"), nullptr);
    s_countp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.vpi_changes"), nullptr);
    s_wp = vpi_handle_by_name(const_cast<PLI_BYTE8*>("t.w"), nullptr);
    if (!yp || !s_countp || !s_wp) {
        vpi_printf(const_cast<PLI_BYTE8*>("%%Error: cannot find t.y, t.w or t.vpi_changes\n"));
        vpi_control(vpiFinish, 1);
        return 0;
    }
    s_vpi_time t;
    t.type = vpiSuppressTime;
    s_vpi_value val;
    val.format = vpiSuppressVal;
    t_cb_data cb_data;
    cb_data.reason = cbValueChange;
    cb_data.cb_rtn = y_change_cb;
    cb_data.obj = yp;
    cb_data.time = &t;
    cb_data.value = &val;
    cb_data.user_data = nullptr;
    vpi_register_cb(&cb_data);
    w_action_at(11, true);
    w_action_at(17, false);
    w_action_at(27, false);
    return 0;
}

static void register_callbacks() {
    s_vpi_time t;
    t.type = vpiSuppressTime;
    t_cb_data cb_data;
    cb_data.reason = cbStartOfSimulation;
    cb_data.cb_rtn = start_of_sim_cb;
    cb_data.obj = nullptr;
    cb_data.time = &t;
    cb_data.value = nullptr;
    cb_data.user_data = nullptr;
    vpi_register_cb(&cb_data);
}

extern "C" {
void (*vlog_startup_routines[])() = {register_callbacks, nullptr};
}
