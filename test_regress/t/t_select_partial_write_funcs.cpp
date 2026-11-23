// -*- mode: C++; c-file-style: "cc-mode" -*-
// DESCRIPTION: Verilator: VL_ASSIGNSEL_PARTIAL_* runtime test
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

#include <cinttypes>
#include <cstdio>
#include <limits>
#include VM_PREFIX_INCLUDE

// Writes a value of obits bits at signed position lsb within a window of wbits bits from bit
// wlsb of a destination of rbits bits, each held in words, by the helper for their widths, and
// checks the destination against writing each bit of the value within the window one by one
// (IEEE 1800-2023 11.5.1)

static constexpr int MAX_WORDS = 5;
using Words = VlWide<MAX_WORDS>;
static int errors = 0;
static uint64_t seed = 0x9e3779b97f4a7c15ULL;

static EData random32() {
    seed ^= seed << 13;
    seed ^= seed >> 7;
    seed ^= seed << 17;
    return static_cast<EData>(seed);
}
static bool bitOf(const Words& words, int bit) {
    return (words[VL_BITWORD_E(bit)] >> VL_BITBIT_E(bit)) & 1;
}
static QData quadOf(const Words& words) {
    return (static_cast<QData>(words[1]) << VL_EDATASIZE) | words[0];
}

// The value's bits above obits are left set, as a dirty value would have them
template <typename T_Narrow>
static void writeNarrow(int rbits, int obits, QData lsb, Words& dst, const Words& val, int wlsb,
                        int wbits) {
    T_Narrow lhs = static_cast<T_Narrow>(dst[0]);
    if (obits <= 32) {
        VL_ASSIGNSEL_PARTIAL_II(rbits, obits, lsb, lhs, val[0], wlsb, wbits);
    } else if (obits <= 64) {
        VL_ASSIGNSEL_PARTIAL_IQ(rbits, obits, lsb, lhs, quadOf(val), wlsb, wbits);
    } else {
        VL_ASSIGNSEL_PARTIAL_IW(rbits, obits, lsb, lhs, val, wlsb, wbits);
    }
    dst[0] = lhs;
}
static void write(int rbits, int obits, QData lsb, Words& dst, const Words& val, int wlsb,
                  int wbits) {
    if (rbits <= 8) {
        writeNarrow<CData>(rbits, obits, lsb, dst, val, wlsb, wbits);
    } else if (rbits <= 16) {
        writeNarrow<SData>(rbits, obits, lsb, dst, val, wlsb, wbits);
    } else if (rbits <= 32) {
        writeNarrow<IData>(rbits, obits, lsb, dst, val, wlsb, wbits);
    } else if (rbits <= 64) {
        QData lhs = quadOf(dst);
        if (obits <= 32) {
            VL_ASSIGNSEL_PARTIAL_QI(rbits, obits, lsb, lhs, val[0], wlsb, wbits);
        } else if (obits <= 64) {
            VL_ASSIGNSEL_PARTIAL_QQ(rbits, obits, lsb, lhs, quadOf(val), wlsb, wbits);
        } else {
            VL_ASSIGNSEL_PARTIAL_QW(rbits, obits, lsb, lhs, val, wlsb, wbits);
        }
        dst[0] = static_cast<EData>(lhs);
        dst[1] = static_cast<EData>(lhs >> VL_EDATASIZE);
    } else if (obits <= 32) {
        VL_ASSIGNSEL_PARTIAL_WI(rbits, obits, lsb, dst, val[0], wlsb, wbits);
    } else if (obits <= 64) {
        VL_ASSIGNSEL_PARTIAL_WQ(rbits, obits, lsb, dst, quadOf(val), wlsb, wbits);
    } else {
        VL_ASSIGNSEL_PARTIAL_WW(rbits, obits, lsb, dst, val, wlsb, wbits);
    }
}

static void check(int rbits, int obits, int64_t pos, int wlsb, int wbits) {
    Words dst;
    Words val;
    for (int i = 0; i < MAX_WORDS; ++i) {
        dst[i] = random32();
        val[i] = random32();
    }
    // A destination is clean
    for (int bit = rbits; bit < MAX_WORDS * VL_EDATASIZE; ++bit) {
        dst[VL_BITWORD_E(bit)] &= ~(EData{1} << VL_BITBIT_E(bit));
    }
    Words exp = dst;
    for (int bit = wlsb; bit < wlsb + wbits; ++bit) {
        const int64_t from = bit - wlsb - pos;
        if (from < 0 || from >= obits) continue;
        const EData mask = EData{1} << VL_BITBIT_E(bit);
        if (bitOf(val, static_cast<int>(from))) {
            exp[VL_BITWORD_E(bit)] |= mask;
        } else {
            exp[VL_BITWORD_E(bit)] &= ~mask;
        }
    }
    write(rbits, obits, static_cast<QData>(pos), dst, val, wlsb, wbits);
    for (int i = 0; i < VL_WORDS_I(rbits); ++i) {
        if (dst[i] != exp[i]) {
            std::printf("%%Error: rbits=%d obits=%d pos=%" PRId64
                        " window=%d+:%d word %d got=%08x exp=%08x\n",
                        rbits, obits, pos, wlsb, wbits, i, dst[i], exp[i]);
            ++errors;
            return;
        }
    }
}

int main(int argc, char** argv) {
    const int rbitsList[] = {2, 7, 8, 13, 16, 31, 32, 33, 63, 64, 65, 100, 130};
    const int obitsList[] = {2, 3, 7, 12, 31, 32, 33, 63, 64, 65, 70, 100, 131};
    for (const int rbits : rbitsList) {
        // The whole destination, and a window within it, as of a packed struct member
        const int windows[][2] = {{0, rbits}, {rbits / 3, rbits - rbits / 3 - 1}};
        for (const auto& window : windows) {
            const int wlsb = window[0];
            const int wbits = window[1];
            if (wbits < 1) continue;
            for (const int obits : obitsList) {
                for (int64_t pos = -obits - 2; pos <= wbits + 2; ++pos) {
                    check(rbits, obits, pos, wlsb, wbits);
                }
                for (const int64_t pos :
                     {std::numeric_limits<int64_t>::min(), std::numeric_limits<int64_t>::max(),
                      int64_t{std::numeric_limits<int32_t>::min()},
                      int64_t{std::numeric_limits<int32_t>::max()} + 1}) {
                    check(rbits, obits, pos, wlsb, wbits);
                }
            }
        }
    }
    if (errors) return 1;
    std::printf("*-* All Finished *-*\n");
    return 0;
}
