// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: svGetScopeFromName finds a package by its own name
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>
#ifdef TEST_VPI
#include <verilated_vpi.h>
#endif

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <svdpi.h>

#include VM_PREFIX_INCLUDE

extern "C" int p_id();
extern "C" void dpic_check();

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            printf("%%Error: %s:%d: CHECK(%s) failed\n", __FILE__, __LINE__, #cond); \
            exit(1); \
        } \
    } while (0)

// Name of the scope found by svGetScopeFromName, or "<none>"
static std::string found(const char* namep) {
    const svScope scope = svGetScopeFromName(namep);
    return scope ? svGetNameFromScope(scope) : "<none>";
}

// Expected result of the next dpic_check call
static std::string s_expName;
static int s_expId = 0;
static int s_checks = 0;

void dpic_check() {
    const svScope importScope = svGetScope();
    const svScope pkgScope = svGetScopeFromName("p");
    CHECK(pkgScope);
    CHECK(svGetNameFromScope(pkgScope) == s_expName);
    const svScope prevScope = svSetScope(pkgScope);
    CHECK(prevScope == importScope);
    CHECK(p_id() == s_expId);
    svSetScope(prevScope);
    CHECK(svGetScope() == importScope);
    ++s_checks;
}

static void runModel(VM_PREFIX* modelp, int id, const char* expNamep, int expId) {
    Verilated::threadContextp(modelp->contextp());
    modelp->id = id;
    s_expName = expNamep;
    s_expId = expId;
    const int checks = s_checks;
    modelp->eval();
    CHECK(s_checks == checks + 1);
}

int main() {
    // Two models in one context
    const std::unique_ptr<VerilatedContext> ctx1{new VerilatedContext};
    std::unique_ptr<VM_PREFIX> ap{new VM_PREFIX{ctx1.get(), "m_a"}};
    std::unique_ptr<VM_PREFIX> bp{new VM_PREFIX{ctx1.get(), "m_b"}};
    Verilated::threadContextp(ctx1.get());

    // Test: without a scope set, only full names find a scope
    CHECK(found("p") == "<none>");
    const svScope aPkgScope = svGetScopeFromName("m_a.p");
    CHECK(aPkgScope);
    CHECK(svGetScopeFromName(svGetNameFromScope(aPkgScope)) == aPkgScope);
    const svScope aTopScope = svGetScopeFromName("m_a.t");
    CHECK(aTopScope);

#ifdef TEST_VPI
    // Test: a package with only a DPI scope is a VPI package, and a top-level instance
    {
        const vpiHandle pkgh = vpi_handle_by_name(const_cast<PLI_BYTE8*>("m_a.p"), nullptr);
        CHECK(pkgh);
        CHECK(vpi_get(vpiType, pkgh) == vpiPackage);
        vpi_release_handle(pkgh);
        bool listed = false;
        const vpiHandle iterh = vpi_iterate(vpiInstance, nullptr);
        CHECK(iterh);
        while (const vpiHandle insth = vpi_scan(iterh)) {
            if (vpi_get(vpiType, insth) == vpiPackage
                && std::string{vpi_get_str(vpiFullName, insth)} == "m_a.p::") {
                listed = true;
            }
            vpi_release_handle(insth);
        }
        CHECK(listed);
    }
#endif

    // Test: within a context import, a package of the model of the import
    runModel(ap.get(), 11, "m_a.p", 11);
    runModel(bp.get(), 12, "m_b.p", 12);

    // Test: the scope set last, also outside an import, selects the model
    CHECK(found("p") == "m_b.p");
    svSetScope(aTopScope);
    CHECK(found("p") == "m_a.p");
    // Test: names other than a package's own name are unchanged
    CHECK(found("t") == "<none>");
    CHECK(found("q") == "<none>");
    CHECK(found("nope") == "<none>");
    CHECK(found("m_b.p") == "m_b.p");
    // Test: a scope of another context is not found
    const std::unique_ptr<VerilatedContext> ctx2{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> cp{new VM_PREFIX{ctx2.get()}};
    Verilated::threadContextp(ctx2.get());
    CHECK(found("p") == "<none>");
    CHECK(found("TOP.p") == "TOP.p");
    Verilated::threadContextp(ctx1.get());
    // Test: clearing the scope leaves only full names
    svSetScope(nullptr);
    CHECK(found("p") == "<none>");
    CHECK(found("m_a.p") == "m_a.p");

    // Test: a model added under the name of a deleted model finds its own package
    bp.reset();
    bp.reset(new VM_PREFIX{ctx1.get(), "m_b"});
    runModel(bp.get(), 13, "m_b.p", 13);
    svSetScope(aTopScope);
    CHECK(found("p") == "m_a.p");
    CHECK(p_id() == 11);
    svSetScope(nullptr);

    // Test: the model named after the default
    runModel(cp.get(), 21, "TOP.p", 21);

    // Test: a model with an empty name, whose package is named by its own name
    const std::unique_ptr<VerilatedContext> ctx3{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> dp{new VM_PREFIX{ctx3.get(), ""}};
    runModel(dp.get(), 31, "p", 31);

    // Test: a full name, if any, has precedence over the own name of a package, also when it is
    // the scope of another model
    const std::unique_ptr<VerilatedContext> ctx4{new VerilatedContext};
    const std::unique_ptr<VM_PREFIX> ep{new VM_PREFIX{ctx4.get(), ""}};
    const std::unique_ptr<VM_PREFIX> fp{new VM_PREFIX{ctx4.get(), "m_f"}};
    runModel(ep.get(), 41, "p", 41);
    runModel(fp.get(), 42, "p", 41);
    svSetScope(svGetScopeFromName("m_f.p"));
    CHECK(p_id() == 42);
    svSetScope(nullptr);

    printf("*-* All Finished *-*\n");
    return 0;
}
