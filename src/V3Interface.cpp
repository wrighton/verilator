// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Interface references for VPI
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
// V3Interface's Transformations:
//
// Each module:
//      Look for CELL...
//          Keep track of scope and concrete interface along the way
//          Find all interface references
//              Add INTFREF to concrete interface's list of references, named
//              relative to the module declaring the interface instance
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Interface.h"

#include <unordered_map>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Track interface references under the Cell they reference

class InlineIntfRefVisitor final : public VNVisitor {
    // NODE STATE
    //   AstVar::user1p()   // AstCell which this Var points to
    const VNUser1InUse m_inuser1;

    string m_scope;  // Scope name
    // Prefix of m_scope naming the first instance of the module declaring each interface
    // instance. References are named relative to it, so all instances share them.
    std::unordered_map<const AstCell*, string> m_declPrefixes;

    // VISITORS
    void visit(AstNetlist* nodep) override { iterateChildrenConst(nodep->topModulep()); }
    void visit(AstCell* nodep) override {
        VL_RESTORER_COPY(m_scope);
        const string prefix = m_scope.empty() ? "" : m_scope + "__DOT__";
        m_scope = prefix + nodep->name();

        AstNodeModule* const modp = nodep->modp();
        // Pass Cell pointers down to the next module
        for (AstPin* const pinp : nodep->pinspList()) {
            AstVar* const varp = pinp->modVarp();
            // TODO: An interface can also propagate upwards and sideways when passed to a port
            //       via a downward hierarchical reference, which is missed here.
            const AstVarRef* const varrefp = VN_CAST(pinp->exprp(), VarRef);
            if (!varrefp) continue;

            const AstVar* const fromVarp = varrefp->varp();
            const AstIfaceRefDType* const irdtp = VN_CAST(fromVarp->dtypep(), IfaceRefDType);
            if (!irdtp) continue;

            AstCell* cellp = VN_CAST(fromVarp->user1p(), Cell);
            if (!cellp) {
                cellp = irdtp->cellp();
                if (!cellp) continue;
                // The interface instance is declared in the module containing this instance
                m_declPrefixes.emplace(cellp, prefix);
            }
            varp->user1p(cellp);
            // Record each reference once, under the first instance of the declaring module
            const string& declPrefix = m_declPrefixes.at(cellp);
            if (!VString::startsWith(m_scope, declPrefix)) continue;
            const string relScope = m_scope.substr(declPrefix.size());
            const string alias = relScope + "__DOT__" + pinp->name();
            // Prefer the port's own dtype; the source may have no modport
            const AstIfaceRefDType* const portIrdtp = VN_CAST(varp->dtypep(), IfaceRefDType);
            const string modportName = portIrdtp ? portIrdtp->modportName() : irdtp->modportName();
            FileLine* const flp = pinp->fileline();
            cellp->addIntfRefsp(new AstIntfRef{flp, alias, relScope, pinp->name(), modportName});
        }

        iterateChildrenConst(modp);
    }
    //--------------------
    void visit(AstNodeExpr*) override {}  // Accelerate
    void visit(AstNodeStmt*) override {}  // Accelerate
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit InlineIntfRefVisitor(AstNode* nodep) { iterateConst(nodep); }
    ~InlineIntfRefVisitor() override = default;
};

//######################################################################
// Interface class functions

void V3Interface::interfaceAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");

    { InlineIntfRefVisitor{nodep}; }

    V3Global::dumpCheckGlobalTree("interface", 0, dumpTreeEitherLevel() >= 3);
}
