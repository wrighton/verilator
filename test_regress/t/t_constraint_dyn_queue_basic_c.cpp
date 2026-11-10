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

// Before main, registers element 10 of an array and element 0 of an array whose name is the
// first name plus a trailing digit in an array element table, keyed as the randomizer keys
// them, and checks each element is looked up as its own. Both escaped-name forms are used:
// with the space ending an escaped identifier, and without one.

#include "verilated_random.h"

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>

namespace {

[[noreturn]] void fail(const char* variantp, const char* whatp) {
    std::fprintf(stderr, "%%Error: array element keys %s: %s\n", variantp, whatp);
    std::fflush(stderr);
    std::_Exit(1);
}

// Elements 'firstBase'[10] and 'secondBase'[0], registered under elemNames
void checkVariant(const char* variantp, const std::string& firstBase,
                  const std::string& secondBase, const std::string& firstElemName,
                  const std::string& secondElemName) {
    IData firstValue = 0x1d;
    IData secondValue = 0x2e;
    VlQueue<IData> firstArray;
    VlQueue<IData> secondArray;
    ArrayInfoMap table;
    table[VlRandomizer::generateKey(firstElemName, 10)] = std::make_shared<const ArrayInfo>(
        firstElemName, &firstValue, 10, std::vector<IData>{10}, std::vector<size_t>{32});
    table[VlRandomizer::generateKey(secondElemName, 0)] = std::make_shared<const ArrayInfo>(
        secondElemName, &secondValue, 0, std::vector<IData>{0}, std::vector<size_t>{32});
    const std::shared_ptr<const ArrayInfoMap> tablep = std::make_shared<const ArrayInfoMap>(table);
    const VlRandomArrayVarTemplate<VlQueue<IData>> firstVar{firstBase, 32, &firstArray, 1, 0};
    const VlRandomArrayVarTemplate<VlQueue<IData>> secondVar{secondBase, 32, &secondArray, 1, 0};
    firstVar.setArrayInfo(tablep);
    secondVar.setArrayInfo(tablep);
    const IData* const firstp = static_cast<const IData*>(firstVar.datap(10));
    const IData* const secondp = static_cast<const IData*>(secondVar.datap(0));
    if (firstp != &firstValue || *firstp != 0x1d) fail(variantp, "first element not its own");
    if (secondp != &secondValue || *secondp != 0x2e) {
        fail(variantp, "second element not its own");
    }
    if (table.size() != 2) fail(variantp, "elements not kept apart");
    std::printf("Array element keys kept apart: %s\n", variantp);
}

struct ArrayKeyCheck final {
    ArrayKeyCheck() {
        checkVariant("escaped with space", "\\esc", "\\esc1", "\\esc [10]", "\\esc1 [0]");
        checkVariant("escaped without space", "\\esc", "\\esc1", "\\esc", "\\esc1");
        std::fflush(stdout);
    }
};

const ArrayKeyCheck s_arrayKeyCheck;

}  // namespace
