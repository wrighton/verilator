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
#include <cstring>
#include <memory>

// These require the above. Comment prevents clang-format moving them
#include "TestSimulator.h"
#include "TestVpi.h"

// As called by the initial process of the library wrapper in another simulator
extern "C" void* sub_protectlib_create(const char* scopep__V);
extern "C" long long sub_protectlib_combo_update(void* vhandlep__V);

static int checkRoot() {
    // The library model created through its wrapper is at the top level
    bool found = false;
    const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
    CHECK_RESULT_NZ(iterp);
    while (const vpiHandle handle = vpi_scan(iterp)) {
        if (std::strcmp(vpi_get_str(vpiFullName, handle), "top.u") == 0) found = true;
        vpi_release_handle(handle);
    }
    CHECK_RESULT(found, true);
    TestVpiHandle handle = vpi_handle_by_name(const_cast<PLI_BYTE8*>("top.u.x"), nullptr);
    CHECK_RESULT_NZ(handle);
    s_vpi_value value;
    value.format = vpiIntVal;
    vpi_get_value(handle, &value);
    CHECK_RESULT(value.value.integer, 7);
    return 0;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    Verilated::threadContextp(contextp.get());
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    void* const libp = sub_protectlib_create("top.u");
    sub_protectlib_combo_update(libp);
    topp->eval();
    if (checkRoot()) return 1;
    topp->final();
    printf("*-* All Finished *-*\n");
    return 0;
}
