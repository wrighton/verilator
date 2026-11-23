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

#include VM_PREFIX_INCLUDE

#include <cstdio>
#include <map>
#include <memory>
#include <set>
#include <string>

// These require the above. Comment prevents clang-format moving them
#include "TestSimulator.h"
#include "TestVpi.h"

static VM_PREFIX* topp = nullptr;

static void tick() {
    topp->clk = 0;
    topp->eval();
    topp->clk = 1;
    topp->eval();
}

// Print the scopes below 'scopep' with their variables, in name order as the order of
// iteration differs between builds
static void walk(vpiHandle scopep, int depth) {
    std::map<std::string, vpiHandle> children;
    // An iterator is freed when its scan ends
    const vpiHandle iterp = vpi_iterate(vpiInternalScope, scopep);
    if (!iterp) return;
    while (const vpiHandle childp = vpi_scan(iterp)) {
        children.emplace(vpi_get_str(vpiFullName, childp), childp);
    }
    for (const auto& itpair : children) {
        const vpiHandle childp = itpair.second;
        printf("%*s%s %s\n", depth * 2, "", vpi_get_str(vpiType, childp), itpair.first.c_str());
        const vpiHandle varIterp = vpi_iterate(vpiReg, childp);
        if (varIterp) {
            while (const vpiHandle varp = vpi_scan(varIterp)) {
                printf("%*s  %s\n", depth * 2, "", vpi_get_str(vpiName, varp));
                vpi_release_handle(varp);
            }
        }
        walk(childp, depth + 1);
        vpi_release_handle(childp);
    }
}

static int getInt(const char* namep) {
    TestVpiHandle handle = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    if (!handle) return -1;
    s_vpi_value value;
    value.format = vpiIntVal;
    vpi_get_value(handle, &value);
    return value.value.integer;
}

static int putInt(const char* namep, int val, PLI_INT32 flags) {
    TestVpiHandle handle = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
    CHECK_RESULT_NZ(handle);
    s_vpi_value value;
    value.format = vpiIntVal;
    value.value.integer = val;
    vpi_put_value(handle, &value, nullptr, flags);
    return 0;
}

static int checkPackages() {
    // Each package found by name is also found by iterating the instances
    std::set<std::string> names;
    const vpiHandle iterp = vpi_iterate(vpiInstance, nullptr);
    CHECK_RESULT_NZ(iterp);
    while (const vpiHandle handle = vpi_scan(iterp)) {
        names.emplace(vpi_get_str(vpiFullName, handle));
        vpi_release_handle(handle);
    }
    int found = 0;
#ifdef T_PARENT_NO_VPI
    // The package of the model without VPI is not in the VPI scope hierarchy
    for (const std::string name : {"top.t.u0.p::", "top.t.u1.p::"}) {
#else
    for (const std::string name : {"top.p::", "top.t.u0.p::", "top.t.u1.p::"}) {
#endif
        const std::string varName = name + "pv";
        TestVpiHandle handle
            = vpi_handle_by_name(const_cast<PLI_BYTE8*>(varName.c_str()), nullptr);
        if (!handle) continue;
        ++found;
        CHECK_RESULT(names.count(name), 1);
    }
    CHECK_RESULT_NZ(found);
    return 0;
}

static int checkAccess() {
#ifndef T_PARENT_NO_VPI
    // The scopes above the instances are found by name, also a generate block and a module
    // with no public variable
    for (const char* const namep : {"top.t", "top.t.GEN_SUB[1]", "top.t.w", "top.t.GEN_RTL[0]",
                                    "top.t.GEN_RTL[0].u_wrap_0"}) {
        TestVpiHandle handle = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
        CHECK_RESULT_NZ(handle);
    }
#endif
    // Also the scopes of nested instances
    for (const char* const namep : {"top.t.GEN_SUB[1].u", "top.t.w.u.l.lv", "top.t.u1.l.lv",
                                    "top.t.GEN_RTL[0].u_wrap_0.u_sub.u_l1",
                                    "top.t.GEN_RTL[0].u_wrap_0.u_sub.u_l1.u_l2.sig"}) {
        TestVpiHandle handle = vpi_handle_by_name(const_cast<PLI_BYTE8*>(namep), nullptr);
        CHECK_RESULT_NZ(handle);
    }
    const int y1 = getInt("top.t.y1");
    // Deposit and force each instance separately, seen through its output in the parent
    if (const int line = putInt("top.t.u0.x", 10, vpiNoDelay)) return line;
    if (const int line = putInt("top.t.GEN_SUB[1].u.x", 30, vpiNoDelay)) return line;
    tick();
    CHECK_RESULT(getInt("top.t.y0"), 10);
    CHECK_RESULT(getInt("top.t.y1"), y1);
    CHECK_RESULT(getInt("top.t.yg[1]"), 30);
    if (const int line = putInt("top.t.u1.x", 20, vpiForceFlag)) return line;
    if (const int line = putInt("top.t.u1.x", 21, vpiNoDelay)) return line;
    tick();
    CHECK_RESULT(getInt("top.t.u1.x"), 20);
    CHECK_RESULT(getInt("top.t.y1"), 20);
    CHECK_RESULT(getInt("top.t.y0"), 10);
    if (const int line = putInt("top.t.u1.x", 0, vpiReleaseFlag)) return line;
    if (const int line = putInt("top.t.u1.x", 22, vpiNoDelay)) return line;
    tick();
    CHECK_RESULT(getInt("top.t.y1"), 22);
    return 0;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> modelp{new VM_PREFIX{contextp.get(), "top"}};
    topp = modelp.get();
    tick();
    walk(nullptr, 0);
    if (checkPackages()) return 1;
    if (checkAccess()) return 1;
    topp->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
