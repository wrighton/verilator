// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Link XREF signals/functions together
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

#ifndef VERILATOR_V3LINKDOT_H_
#define VERILATOR_V3LINKDOT_H_

#include "config_build.h"
#include "verilatedos.h"

#include "V3Ast.h"
#include "V3Error.h"

//============================================================================

enum VLinkDotStep : uint8_t { LDS_PRIMARY, LDS_PARAMED, LDS_SCOPED };

class V3LinkDot final {
    static void dumpSubstep(const string& name) VL_MT_DISABLED;
    static void linkDotGuts(AstNetlist* rootp, VLinkDotStep step) VL_MT_DISABLED;

public:
    // Components of a hierarchical instance path, as of a defparam, each with the index
    // selecting a generate loop iteration, if any
    using PathSegments = std::vector<std::pair<std::string, AstNodeExpr*>>;
    // Append the components of pathp to segs, folding each index of constants only to a
    // constant; return false if a component has other than one index
    static bool pathSegments(AstNode* pathp, PathSegments& segs) VL_MT_DISABLED;

    static void linkDotPrimary(AstNetlist* nodep) VL_MT_DISABLED;
    static void linkDotParamed(AstNetlist* nodep) VL_MT_DISABLED;
    static void linkDotScope(AstNetlist* nodep) VL_MT_DISABLED;
    // Describe the kind of declaration nodep is for messages, e.g. "variable"
    static string nodeTextType(AstNode* nodep) VL_MT_DISABLED;
};

#endif  // Guard
