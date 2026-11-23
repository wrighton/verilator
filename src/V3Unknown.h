// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Add Unknown assigns
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2003-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#ifndef VERILATOR_V3UNKNOWN_H_
#define VERILATOR_V3UNKNOWN_H_

#include "config_build.h"
#include "verilatedos.h"

class AstNetlist;
class AstNodeExpr;

//============================================================================

class V3Unknown final {
public:
    static void unknownAll(AstNetlist* nodep) VL_MT_DISABLED;
    // Return an upper bound of the unsigned value of 'exprp'
    static uint64_t staticMax(const AstNodeExpr* exprp) VL_MT_DISABLED;
    // Split the writes of part-selects marked partialWrite, once scheduled
    static void partialWritesAll(AstNetlist* nodep) VL_MT_DISABLED;
};

#endif  // Guard
