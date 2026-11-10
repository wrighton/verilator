// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test defines
#define MAIN_TIME_MULTIPLIER 1
#include <memory>
// OS header
#include "verilatedos.h"
// Generated header
#include VM_PREFIX_INCLUDE
// General headers
#include "verilated.h"
#include "verilated_force.h"

std::unique_ptr<VM_PREFIX> topp;

template <typename T>
void checkRhsStorage(T value, int width) {
    VlForceVec forces;
    forces.addForce(0, width - 1, &value, 0);
    if (forces.read(T{0}) != value) vl_fatal(__FILE__, __LINE__, "", "RHS storage mismatch");
    const int kept = width / 2;
    const T lowMask = static_cast<T>(VL_MASK_Q(kept));
    forces.release(kept, width - 1);
    if (forces.read(T{0}) != static_cast<T>(value & lowMask))
        vl_fatal(__FILE__, __LINE__, "", "Tail trim lost RHS storage width");
    forces.addForce(0, width - 1, &value, 0);
    forces.release(0, kept - 1);
    if (forces.read(T{0}) != static_cast<T>(value & ~lowMask))
        vl_fatal(__FILE__, __LINE__, "", "Head trim lost RHS storage width");
    forces.addForce(0, width - 1, &value, 0);
    forces.release(1, width - 2);
    const T ends = static_cast<T>(T{1} | (T{1} << (width - 1)));
    if (forces.read(T{0}) != static_cast<T>(value & ends))
        vl_fatal(__FILE__, __LINE__, "", "Middle trim lost RHS storage width");
    forces.release(0, width - 1);
    if (forces.read(T{0}) != 0) vl_fatal(__FILE__, __LINE__, "", "RHS release mismatch");
}

int main(int argc, char** argv) {
    checkRhsStorage(CData{0x65}, 7);
    checkRhsStorage(SData{0x4567}, 15);
    checkRhsStorage(IData{0x5a123456}, 31);
    checkRhsStorage(QData{0x5123456789abcdefULL}, 63);
    alignas(QData) CData misaligned[9] = {};
    misaligned[1] = 5;
    VlForceVec narrow;
    narrow.addForce(0, 2, misaligned + 1, 0);
    if (narrow.read(CData{0}) != 5)
        vl_fatal(__FILE__, __LINE__, "", "Misaligned narrow RHS mismatch");
    const CData bits = 5;
    VlForceVec element;
    element.addForce(1, 1, &bits, 9, 9, 11, 63);
    if (element.readIndex(QData{0}, 1) != QData{5 << 9})
        vl_fatal(__FILE__, __LINE__, "", "Narrow element RHS mismatch");
    element.release(1, 1, 10, 10);
    if (element.readIndex(QData{0}, 1) != QData{5 << 9})
        vl_fatal(__FILE__, __LINE__, "", "Element split lost RHS storage width");
    const SData wideBits = 0x5a5;
    VlForceVec wideElement;
    wideElement.addForce(2, 2, &wideBits, 60, 60, 70, 95);
    VlWide<3> zero = {};
    const VlWide<3> blended = wideElement.readIndex(zero, 2);
    if (blended[0] || blended[1] != 0x50000000U || blended[2] != 0x5aU)
        vl_fatal(__FILE__, __LINE__, "", "Wide element narrow RHS mismatch");
    wideElement.release(2, 2, 65, 68);
    const VlWide<3> split = wideElement.readIndex(zero, 2);
    if (split[0] || split[1] != 0x50000000U || split[2] != 0x40U)
        vl_fatal(__FILE__, __LINE__, "", "Wide element split lost RHS storage width");
    VlWide<3> wideRhs = {};
    wideRhs[0] = 0x89abcdefU;
    wideRhs[1] = 0x12345678U;
    wideRhs[2] = 0x13579bdfU;
    VlForceVec wide;
    wide.addForce(0, 94, &wideRhs, 0);
    if (wide.read(zero) != wideRhs) vl_fatal(__FILE__, __LINE__, "", "Wide RHS mismatch");
    wide.release(32, 94);
    const VlWide<3> trimmed = wide.read(zero);
    if (trimmed[0] != wideRhs[0] || trimmed[1] || trimmed[2])
        vl_fatal(__FILE__, __LINE__, "", "Wide trim lost RHS storage width");
    uint64_t sim_time = 1100;
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    contextp->debug(0);
    srand48(5);
    topp.reset(new VM_PREFIX{"top"});
    topp->topin = 0x9;
    topp->eval();
    {
        topp->clk = false;
        contextp->timeInc(10 * MAIN_TIME_MULTIPLIER);
    }
    while ((contextp->time() < sim_time * MAIN_TIME_MULTIPLIER) && !contextp->gotFinish()) {
        topp->clk = !topp->clk;
        topp->eval();
        contextp->timeInc(1 * MAIN_TIME_MULTIPLIER);
        contextp->timeInc(1 * MAIN_TIME_MULTIPLIER);
        contextp->timeInc(1 * MAIN_TIME_MULTIPLIER);
        contextp->timeInc(1 * MAIN_TIME_MULTIPLIER);
        contextp->timeInc(1 * MAIN_TIME_MULTIPLIER);
    }
    if (!contextp->gotFinish()) {
        vl_fatal(__FILE__, __LINE__, "main", "%Error: Timeout; never got a $finish");
    }
    topp->final();

    topp.reset();
    return 0;
}
