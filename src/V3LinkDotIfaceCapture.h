// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Interface typedef capture helper.
//   Records RefDTypes that reach an interface typedef through a cell path, so
//   V3Param clones can retarget them to the correct interface specialization.
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

#ifndef VERILATOR_V3LINKDOTIFACECAPTURE_H_
#define VERILATOR_V3LINKDOTIFACECAPTURE_H_

#include "config_build.h"

#include "V3Ast.h"

#include <deque>
#include <functional>
#include <string>
#include <unordered_map>
#include <unordered_set>

class VSymEnt;

// Capture record of an AstRefDType, shared by all clones of that reference
class VIfaceCaptureTag final {
public:
    enum class Kind : uint8_t {
        TYPEDEF,  // Refers to a typedef in the interface
        PARAM_TYPE  // Refers to a type parameter of the interface
    };
    Kind m_kind;  // What the reference refers to
    string m_cellPath;  // Cell path from the owner module (e.g. "cca_io.tlb_io")
    string m_ownerModName;  // Name of the interface that owns the target
    string m_capturedInName;  // Original name of the module the reference was captured in
};

class V3LinkDotIfaceCapture final {
    static std::deque<VIfaceCaptureTag> s_tags;  // Owns every tag; a deque keeps addresses stable
    // Original module name -> cellPathKey of the paths of the references captured in it. Static
    // like s_tags, grown by tag() and cleared with s_tags by reset().
    static std::unordered_map<string, std::unordered_set<string>> s_cellPaths;
    static bool s_enabled;

    // --- Internal-only methods (not called outside V3LinkDotIfaceCapture.cpp) ---
    static void enable(bool flag);  // LCOV_EXCL_LINE
    // Last cell of a cell path without its array index, so paths through generate blocks or
    // instance arrays to a cell of a name share it
    static string cellPathKey(const string& cellPath);
    static void reset();
    static void clearModuleCache();
    static AstIfaceRefDType* ifaceRefFromVarDType(AstNodeDType* dtypep);
    // Point a reference at a typedef and fix its other links.
    static void retargetRefToTypedef(AstRefDType* refp, AstTypedef* typedefp);
    // Same, for a parameter type.
    static void retargetRefToParamType(AstRefDType* refp, AstParamTypeDType* paramTypep);
    // Tag a reference captured in capturedInp
    static void tag(AstRefDType* refp, const AstNodeModule* capturedInp,
                    VIfaceCaptureTag::Kind kind, const string& cellPath,
                    const string& ownerModName);
    static int resolveCapturedRefs();
    static void verifyNoDeadRefs();

public:
    static bool enabled() { return s_enabled; }
    // Tag of a reference, or nullptr if untagged or copied into another module
    static const VIfaceCaptureTag* captureTag(AstRefDType* refp);
    // Whether a reference captured in modp's original module may have a cell path to cellName,
    // ignoring the generate blocks and array indices on the way
    static bool hasCapture(const AstNodeModule* modp, const string& cellName);
    static AstNodeModule* findOwnerModule(AstNode* nodep);
    // Find a Typedef by name in a module's top-level statements
    static AstTypedef* findTypedefInModule(AstNodeModule* modp, const string& name);
    // Find a NodeDType by name and VNType in a module's top-level statements
    static AstNodeDType* findDTypeInModule(AstNodeModule* modp, const string& name, VNType type);
    // Find a ParamTypeDType by name in a module's top-level statements
    static AstParamTypeDType* findParamTypeInModule(AstNodeModule* modp, const string& name);
    // Retarget a captured reference at the same-named target in targetModp.
    static bool retargetRefToModule(AstRefDType* refp, AstNodeModule* targetModp);
    static void addParamType(AstRefDType* refp, const string& cellPath, AstNodeModule* ownerModp,
                             AstParamTypeDType* paramTypep, const string& paramTypeOwnerModName);

    // Walk a dot-separated cell path (e.g. "cca_io.tlb_io") starting from
    // startModp, returning the module at the end of the path.  Returns
    // nullptr if any component cannot be resolved.
    static AstNodeModule* followCellPath(const AstNodeModule* startModp, const string& cellPath);

    static void captureTypedefContext(AstRefDType* refp, const char* stageLabel, int dotPos,
                                      const std::string& dotText, VSymEnt* dotSymp,
                                      AstNodeModule* modp,
                                      const std::function<std::string()>& indentFn);

    // Debug: dump all captured references
    static void dumpEntries(const string& label);

    // Called after V3Param but before V3Dead to fix any remaining cross-interface refs
    // that still point to template nodes (which will be deleted by V3Dead).
    static void finalizeIfaceCapture();
};

#endif  // VERILATOR_V3LINKDOTIFACECAPTURE_H_
