// ======================================================================
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Christian Hecken
// SPDX-License-Identifier: CC0-1.0
// ======================================================================

// DESCRIPTION: Scope hierarchy map upon VerilatedModel construction and destruction
//
// VerilatedImp::s() is a VerilatedImpData singleton that contains an m_hierMap
// whose keys are pointers to VerilatedScope objects. Because it is a
// singleton shared by all models, this test checks that destroying a model
// removes the keys of its scopes, but keeps the scope hierarchy of the other
// models, including while it is being iterated.

// Workaround to be able to include verilated_imp.h, needed to directly test the hierarchy map
#define VERILATOR_VERILATED_CPP_
#include "verilated_imp.h"
#include <verilated.h>
#include <verilated_vpi.h>

#include "TestCheck.h"
#include VM_PREFIX_INCLUDE

#include <memory>

int errors = 0;

// Scan the rest of an iteration, returning the number of objects
static int scanCount(vpiHandle iterp) {
    int count = 0;
    if (!iterp) return count;
    while (const vpiHandle objp = vpi_scan(iterp)) {
        ++count;
        vpi_release_handle(objp);
    }
    return count;
}

static int moduleCount(vpiHandle parentp) { return scanCount(vpi_iterate(vpiModule, parentp)); }

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextAp{new VerilatedContext};
    const std::unique_ptr<VerilatedContext> contextBp{new VerilatedContext};
    const std::unique_ptr<VerilatedContext> contextCp{new VerilatedContext};
    contextAp->commandArgs(argc, argv);

    {
        // Construct and destroy
        const size_t emptySize = VerilatedImp::hierarchyMap()->size();
        {
            // Note null name - we're flattening it out
            const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextAp.get(), ""}};
            TEST_CHECK_NE(VerilatedImp::hierarchyMap()->size(), emptySize);
        }
        TEST_CHECK_EQ(VerilatedImp::hierarchyMap()->size(), emptySize);
    }

    std::unique_ptr<VM_PREFIX> topAp{new VM_PREFIX{contextAp.get(), ""}};
    std::unique_ptr<VM_PREFIX> topBp{new VM_PREFIX{contextBp.get(), ""}};
    TEST_CHECK_EQ(moduleCount(nullptr), 2);
    // Top modules iterate in construction order
    const vpiHandle topsIterp = vpi_iterate(vpiModule, nullptr);
    vpi_release_handle(vpi_scan(topsIterp));
    const vpiHandle topBh = vpi_scan(topsIterp);
    TEST_CHECK_NZ(topBh);
    vpi_release_handle(topsIterp);
    TEST_CHECK_EQ(moduleCount(topBh), 1);

    {
        // Iterating the top modules while another model is constructed
        const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
        vpi_release_handle(vpi_scan(iterp));
        std::unique_ptr<VM_PREFIX> topCp{new VM_PREFIX{contextCp.get(), ""}};
        const int count = scanCount(iterp);
        TEST_CHECK_EQ(count, 1);
    }

    {
        // Iterating the scopes of a model while another model is destroyed
        const vpiHandle iterp = vpi_iterate(vpiModule, topBh);
        topAp.reset();
        const int count = scanCount(iterp);
        TEST_CHECK_EQ(count, 1);
        TEST_CHECK_EQ(moduleCount(topBh), 1);
        TEST_CHECK_EQ(moduleCount(nullptr), 1);
    }

    {
        // Iterating the top modules while the visited model is destroyed
        topAp.reset(new VM_PREFIX{contextAp.get(), ""});
        std::unique_ptr<VM_PREFIX> topCp{new VM_PREFIX{contextCp.get(), ""}};
        const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
        vpi_release_handle(vpi_scan(iterp));  // Model B's top
        vpi_release_handle(topBh);
        topBp.reset();
        const int count = scanCount(iterp);
        TEST_CHECK_EQ(count, 2);
    }

    {
        // Iterating the top modules while the model of a later one is destroyed
        topBp.reset(new VM_PREFIX{contextBp.get(), ""});
        const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
        vpi_release_handle(vpi_scan(iterp));  // Model A's top
        topBp.reset();
        const int count = scanCount(iterp);
        TEST_CHECK_EQ(count, 0);
    }

    {
        // Iterating the top modules while the last model is destroyed
        const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
        topAp.reset();
        const int count = scanCount(iterp);
        TEST_CHECK_EQ(count, 0);
    }

    {
        // Iterating the top modules while the last model is destroyed and another created,
        // which may reuse the address of the destroyed top scope, so may be returned
        topAp.reset(new VM_PREFIX{contextAp.get(), ""});
        const vpiHandle iterp = vpi_iterate(vpiModule, nullptr);
        topAp.reset();
        topBp.reset(new VM_PREFIX{contextBp.get(), ""});
        const int count = scanCount(iterp);
        TEST_CHECK(count, "0 or 1", count <= 1);
    }

    if (!errors) VL_PRINTF("*-* All Finished *-*\n");
    return errors ? 10 : 0;
}
