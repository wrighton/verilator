// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// Code available from: https://verilator.org
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
///
/// \file
/// \brief Internal limits shared by DIST code generation and sampling
///
/// This file is not part of the Verilated public-facing API.
/// It is only for internal use.
///
//*************************************************************************
#ifndef VERILATOR_VERILATED_RAND_LIMITS_H_
#define VERILATOR_VERILATED_RAND_LIMITS_H_

#include <cstddef>

namespace VlRandLimits {
// Limit operand size independently of the number of expressions in a site.
// At 1024 bits an operand uses at most 32 words before cardinality/carry bits.
static constexpr unsigned distMaxBits = 1024;
static constexpr int diversityMaxChecks = 512;  // Most checks to spread one satisfying solution
static constexpr unsigned distMaxItems = 341;  // Up to 1023 bound and weight terms per site
static constexpr unsigned distMaxWork = 1 << 18;  // Word operations allowed per call
// Leave room for the rest of the model and work whose size is known only at runtime.
static constexpr unsigned distStaticMaxWork = distMaxWork * 7 / 8;
static constexpr std::size_t distChoiceWork(std::size_t items, unsigned words) {
    return words * (3 + 2 * items);  // Sum and walk bucket masses for one selection
}
static constexpr std::size_t distTextWork(std::size_t bytes) {
    return bytes / 4 + (bytes % 4 != 0);  // Round up to 32-bit work units
}
static constexpr std::size_t distBucketTextWork(std::size_t targetBytes, std::size_t lowBytes,
                                                std::size_t highBytes) {
    constexpr std::size_t overhead = 40;  // Connectives and delimiters
    return distTextWork(overhead + targetBytes + lowBytes
                        + (highBytes ? targetBytes + highBytes : 0));
}
// A sign/cardinality bit and enough carry bits for all the buckets in one site.
static constexpr unsigned distWords(unsigned bits) { return (bits + 1 + 10 + 31) / 32; }
// VL_MUL_W clears words, iterates words squared products, and adds a
// triangular number of carries per nonempty product row.
static constexpr unsigned distSiteWork(unsigned items, unsigned words, unsigned perValueItems) {
    const unsigned mulWork = words + words * words + words * (words + 1) * (words + 2) / 6;
    return items * words * (3 + words) + perValueItems * mulWork;
}
}  // namespace VlRandLimits

#endif  // guard
