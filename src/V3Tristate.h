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

#ifndef VERILATOR_V3TRISTATE_H_
#define VERILATOR_V3TRISTATE_H_

#include "config_build.h"
#include "verilatedos.h"

#include <unordered_set>

class AstNetlist;
class AstVar;

//============================================================================

// Ports every instance of which connects a value carried from an inout port, found by
// V3Tristate::prepareForcePorts before constants fold the expressions carrying them, for
// V3Tristate::tristateAll: input ports that do not collapse with their connections, and inout
// ports that keep the lowering of an ordinary port when forced
class V3TristateForcePorts final {
public:
    std::unordered_set<const AstVar*> inputps;
    std::unordered_set<const AstVar*> inoutps;
};

//============================================================================

class V3Tristate final {
public:
    static void prepareForcePorts(AstNetlist* nodep,
                                  V3TristateForcePorts& forcePorts) VL_MT_DISABLED;
    static void tristateAll(AstNetlist* nodep,
                            const V3TristateForcePorts& forcePorts) VL_MT_DISABLED;
};

#endif  // Guard
