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

// Count the value changes of 't.y' and 't.c' into 't.vpi_changes' and 't.vpi_c_changes', and
// force and release 't.w', 't.m' and 't.c' at set times

static vpiHandle handle(const char* namep) {
    vpiHandle const objp = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    if (!objp) {
        vpi_printf(const_cast<PLI_BYTE8*>("%%Error: cannot find %s\n"), namep);
        vpi_control(vpiFinish, 1);
    }
    return objp;
}

static void put(vpiHandle objp, PLI_INT32 value, PLI_INT32 flag) {
    s_vpi_value val;
    val.format = vpiIntVal;
    val.value.integer = value;
    vpi_put_value(objp, &val, nullptr, flag);
}

static PLI_INT32 get(vpiHandle objp) {
    s_vpi_value val;
    val.format = vpiIntVal;
    vpi_get_value(objp, &val);
    return val.value.integer;
}

static vpiHandle s_yChangesp = nullptr;
static vpiHandle s_cChangesp = nullptr;
static vpiHandle s_wp = nullptr;
static vpiHandle s_mp = nullptr;
static vpiHandle s_cp = nullptr;
static int s_yChanges = 0;
static int s_cChanges = 0;

static PLI_INT32 y_change_cb(p_cb_data /*cb_data*/) {
    put(s_yChangesp, ++s_yChanges, vpiNoDelay);
    return 0;
}

static PLI_INT32 c_change_cb(p_cb_data cb_data) {
    put(s_cChangesp, ++s_cChanges, vpiNoDelay);
    if (cb_data->value->value.integer == 1) put(s_cp, 0, vpiForceFlag);
    return 0;
}

static PLI_INT32 action_cb(p_cb_data /*cb_data*/) {
    s_vpi_time now;
    now.type = vpiSimTime;
    vpi_get_time(nullptr, &now);
    switch (now.low) {
    case 6: put(s_mp, 0x55, vpiForceFlag); break;
    case 11: put(s_wp, get(s_wp), vpiForceFlag); break;  // Hold its value
    case 17:
    case 27: put(s_wp, 0, vpiReleaseFlag); break;
    case 31: put(s_cp, 1, vpiForceFlag); break;
    default: break;
    }
    return 0;
}

static void register_cb(PLI_INT32 reason, PLI_INT32 (*cb_rtn)(p_cb_data), vpiHandle objp,
                        PLI_UINT32 time) {
    s_vpi_time t;
    t.type = time ? vpiSimTime : vpiSuppressTime;
    t.high = 0;
    t.low = time;
    s_vpi_value val;
    val.format = vpiIntVal;
    t_cb_data cb_data;
    cb_data.reason = reason;
    cb_data.cb_rtn = cb_rtn;
    cb_data.obj = objp;
    cb_data.time = &t;
    cb_data.value = &val;
    cb_data.user_data = nullptr;
    vpi_register_cb(&cb_data);
}

static PLI_INT32 start_of_sim_cb(p_cb_data /*cb_data*/) {
    s_yChangesp = handle("t.vpi_changes");
    s_cChangesp = handle("t.vpi_c_changes");
    s_wp = handle("t.w");
    s_mp = handle("t.m");
    s_cp = handle("t.c");
    register_cb(cbValueChange, y_change_cb, handle("t.y"), 0);
    register_cb(cbValueChange, c_change_cb, s_cp, 0);
    static const PLI_UINT32 s_actionTimes[] = {6, 11, 17, 27, 31};
    for (const PLI_UINT32 time : s_actionTimes)
        register_cb(cbAfterDelay, action_cb, nullptr, time);
    return 0;
}

static void register_callbacks() { register_cb(cbStartOfSimulation, start_of_sim_cb, nullptr, 0); }

extern "C" {
void (*vlog_startup_routines[])() = {register_callbacks, nullptr};
}
