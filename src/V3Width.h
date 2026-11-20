// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Node attributes/ expression widths
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

#ifndef VERILATOR_V3WIDTH_H_
#define VERILATOR_V3WIDTH_H_

#include "config_build.h"
#include "verilatedos.h"

class AstConst;
class AstSel;
class AstNetlist;
class AstNode;
class AstNodeAssign;
class AstNodeDType;

//============================================================================

class V3Width final {
public:
    static void width(AstNetlist* nodep) VL_MT_DISABLED;
    static AstNode* widthParamsEdit(AstNode* nodep) VL_MT_DISABLED;
    static AstNode* widthGenerateParamsEdit(AstNode* nodep) VL_MT_DISABLED;
    static AstNode* selectNonConstantRecurse(AstNode* nodep, bool inSel = false) VL_MT_DISABLED;
    static void streamAssignLowerEdit(AstNodeAssign* nodep) VL_MT_DISABLED;

    // For use only in WidthVisitor
    // Replace AstSelBit, etc with AstSel/AstArraySel
    // Returns replacement node if nodep was deleted, or null if none.
    // The type of a constant position, as written, from which a storage offset was computed
    struct SelOrigin final {
        bool valid = false;
        int width = 0;
        int widthMin = 0;
        bool sized = false;
    };
    static AstNode* widthSelNoIterEdit(AstNode* nodep,
                                       SelOrigin* originp = nullptr) VL_MT_DISABLED;
    // Whether a constant select position is read as signed: a 32-bit position is an integer
    static bool selectPositionSigned(const AstConst* constp) VL_MT_DISABLED;
    // Warn that a constant select is out of range, in its declared coordinates
    // afterWidth: the select was already widthed, as its position is read differently
    static void warnSelectRange(AstSel* nodep, bool afterWidth) VL_MT_DISABLED;
};

#endif  // Guard
