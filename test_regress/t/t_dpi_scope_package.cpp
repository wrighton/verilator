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
#include <future>
#include <memory>
#include <string>
#include <svdpi.h>
#include <thread>

#include VM_PREFIX_INCLUDE

extern "C" int p_id();
extern "C" int q_id();
extern "C" int pq_id();
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
        CHECK(std::string{vpi_get_str(vpiFullName, pkgh)} == "m_a.p::");
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
        // Test: the name of an escaped package is all of its name
        const vpiHandle escapedh = vpi_handle_by_name(const_cast<PLI_BYTE8*>("m_a.p.q"), nullptr);
        CHECK(escapedh);
        CHECK(vpi_get(vpiType, escapedh) == vpiPackage);
        CHECK(std::string{vpi_get_str(vpiName, escapedh)} == "p.q");
        CHECK(std::string{vpi_get_str(vpiFullName, escapedh)} == "m_a.p.q::");
        vpi_release_handle(escapedh);
    }
#endif

    // Test: within a context import, a package of the model of the import
    runModel(ap.get(), 11, "m_a.p", 11);
    runModel(bp.get(), 12, "m_b.p", 12);

    // Test: the scope set last, also outside an import, selects the model
    CHECK(found("p") == "m_b.p");
    svSetScope(aTopScope);
    CHECK(found("p") == "m_a.p");
    // Test: a package by its own name, also an escaped name, but not by a part of it
    CHECK(found("q") == "m_a.q");
    svSetScope(svGetScopeFromName("q"));
    CHECK(q_id() == 111);
    svSetScope(aTopScope);
    CHECK(found("p.q") == "m_a.p.q");
    svSetScope(svGetScopeFromName("p.q"));
    CHECK(pq_id() == 211);
    svSetScope(aTopScope);
    CHECK(found("s") == "<none>");
    CHECK(found("r.s") == "m_a.r.s");
    CHECK(found("m_a.p.q") == "m_a.p.q");
    // Test: names other than a package's own name are unchanged
    CHECK(found("t") == "<none>");
    CHECK(found("z") == "<none>");
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

    // Test: the scope set by an import of a deleted model selects no model
    const std::unique_ptr<VerilatedContext> ctx5{new VerilatedContext};
    std::unique_ptr<VM_PREFIX> gp{new VM_PREFIX{ctx5.get(), "m_g"}};
    const std::unique_ptr<VM_PREFIX> hp{new VM_PREFIX{ctx5.get(), "m_h"}};
    runModel(hp.get(), 52, "m_h.p", 52);
    runModel(gp.get(), 51, "m_g.p", 51);
    gp.reset();
    CHECK(found("p") == "<none>");
    CHECK(found("nope") == "<none>");
    CHECK(found("m_h.p") == "m_h.p");
    // Test: as the scope saved and set again by svSetScope
    const svScope hTopScope = svGetScopeFromName("m_h.t");
    CHECK(hTopScope);
    const svScope deletedScope = svSetScope(hTopScope);
    CHECK(found("p") == "m_h.p");
    svSetScope(deletedScope);
    CHECK(found("p") == "<none>");
    // Test: also when another model is added
    std::unique_ptr<VM_PREFIX> kp{new VM_PREFIX{ctx5.get(), "m_k"}};
    CHECK(found("p") == "<none>");
    CHECK(found("m_k.p") == "m_k.p");
    // Test: deleting a model other than the one of the scope set keeps its selection
    svSetScope(hTopScope);
    kp.reset();
    CHECK(found("p") == "m_h.p");
    {
        const std::unique_ptr<VerilatedContext> ctx6{new VerilatedContext};
        std::unique_ptr<VM_PREFIX>{new VM_PREFIX{ctx6.get(), "m_other"}};
    }
    Verilated::threadContextp(ctx5.get());
    CHECK(found("p") == "m_h.p");
    // Test: a scope set while it is not of the thread's context selects no model
    Verilated::threadContextp(ctx1.get());
    svSetScope(hTopScope);
    Verilated::threadContextp(ctx5.get());
    CHECK(found("p") == "<none>");
    svSetScope(hTopScope);
    CHECK(found("p") == "m_h.p");
    // Test: a model added again under a deleted model's name selects itself
    kp.reset(new VM_PREFIX{ctx5.get(), "m_k"});
    runModel(kp.get(), 54, "m_k.p", 54);
    // Test: the scope set by an import on another thread, after the model is deleted
    std::unique_ptr<VM_PREFIX> mp{new VM_PREFIX{ctx5.get(), "m_m"}};
    std::promise<void> ranPromise;
    std::promise<void> deletedPromise;
    std::thread thread{[&]() {
        runModel(mp.get(), 55, "m_m.p", 55);
        ranPromise.set_value();
        deletedPromise.get_future().wait();
        Verilated::threadContextp(ctx5.get());
        CHECK(found("p") == "<none>");
        CHECK(found("m_h.p") == "m_h.p");
    }};
    ranPromise.get_future().wait();
    mp.reset();
    deletedPromise.set_value();
    thread.join();

    printf("*-* All Finished *-*\n");
    return 0;
}
