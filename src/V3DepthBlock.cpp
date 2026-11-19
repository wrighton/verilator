// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Prevent very deep expressions
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
// V3DepthBlock's Transformations:
//
// Each module:
//      For each deep block, create cfunc including that block, passing it the local
//      variables of the function that the block references.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3DepthBlock.h"

#include "V3EmitCBase.h"
#include "V3Outline.h"

#include <algorithm>
#include <limits>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Mark the statements of a function that cannot move into another function

class DepthBlockFixedVisitor final : public VNVisitorConst {
    // A statement cannot move if it returns from the function, or tests the condition of a
    // loop around it

    // NODE STATE
    //  AstNodeStmt::user1()  -> bool. Cannot move into another function (set here)
    //  AstLoop::user2()      -> int. Nesting depth
    const VNUser2InUse m_user2InUse;

    // STATE
    int m_depth = 0;  // Nesting depth of the current statement
    int m_targetDepth = 0;  // Least depth of the loops tested, or 0 if returning, under it

    // VISITORS
    void visit(AstNodeStmt* nodep) override {
        VL_RESTORER(m_depth);
        const int outerTargetDepth = m_targetDepth;
        ++m_depth;
        m_targetDepth = std::numeric_limits<int>::max();
        if (AstLoop* const loopp = VN_CAST(nodep, Loop)) loopp->user2(m_depth);
        if (const AstLoopTest* const testp = VN_CAST(nodep, LoopTest)) {
            m_targetDepth = testp->loopp()->user2();
        }
        if (VN_IS(nodep, CReturn) || VN_IS(nodep, FinishFork)) m_targetDepth = 0;
        iterateChildrenConst(nodep);
        nodep->user1(m_targetDepth < m_depth);
        m_targetDepth = std::min(m_targetDepth, outerTargetDepth);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit DepthBlockFixedVisitor(AstCFunc* nodep) { iterateChildrenConst(nodep); }
};

//######################################################################

class DepthBlockVisitor final : public VNVisitor {
    // NODE STATE
    //  AstNodeStmt::user1()  -> bool. Cannot move into another function (DepthBlockFixedVisitor)
    const VNUser1InUse m_user1InUse;

    // STATE - for current visit position (use VL_RESTORER)
    const AstNodeModule* m_modp = nullptr;  // Current module
    const AstCFunc* m_cfuncp = nullptr;  // Current function
    int m_depth = 0;  // How deep in an expression
    int m_deepNum = 0;  // How many functions made
    // In a function made here. Its statements keep the marks made for the function they came
    // from, so they are not analyzed again for each new function.
    bool m_deepFunc = false;

    // METHODS
    // Make a function of unlinked statement 'nodep', return a call of it, not yet linked
    AstCCall* createDeepFunc(AstNodeStmt* nodep) {
        // Create sub function
        AstScope* const scopep = m_cfuncp->scopep();
        const string name = m_cfuncp->name() + "__deep" + cvtToStr(++m_deepNum);
        AstCFunc* const funcp = new AstCFunc{nodep->fileline(), name, scopep};
        funcp->slow(m_cfuncp->slow());
        funcp->isStatic(m_cfuncp->isStatic());
        funcp->isLoose(m_cfuncp->isLoose());
        if (m_cfuncp->needsVlProcess()) funcp->setNeedsVlProcess();
        funcp->addStmtsp(nodep);
        scopep->addBlocksp(funcp);
        // Call sub function at the point where the body was removed from
        AstCCall* const callp = new AstCCall{nodep->fileline(), funcp};
        callp->dtypeSetVoid();
        if (VN_IS(m_modp, Class)) {
            funcp->argTypes(EmitCUtil::symClassVar());
            callp->argTypes("vlSymsp");
        }
        UINFO(6, "      New " << callp);
        return callp;
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        UINFO(4, " MOD   " << nodep);
        VL_RESTORER(m_modp);
        m_modp = nodep;
        m_deepNum = 0;
        iterateChildren(nodep);
    }
    void visit(AstCFunc* nodep) override {
        // We recurse into this.
        VL_RESTORER(m_depth);
        VL_RESTORER(m_cfuncp);
        m_depth = 0;
        m_cfuncp = nodep;
        // Statements moved into a new function keep their marks
        if (!m_deepFunc) { DepthBlockFixedVisitor{nodep}; }
        iterateChildren(nodep);
    }
    void visit(AstStmtExpr* nodep) override {}  // Stop recursion after introducing new function
    void visit(AstCAwait* nodep) override {}  // Likewise, for a new function that suspends
    void visit(AstJumpBlock*) override {}  // Stop recursion as can't break up across a jump
    void visit(AstNodeStmt* nodep) override {
        ++m_depth;
        if (m_depth > v3Global.opt.compLimitBlocks() && !nodep->user1()) {  // Already done
            UINFO(4, "DeepBlocks " << m_depth << " " << nodep);
            const AstNode* const backp = nodep->backp();  // Only for debug
            UINFOTREE(9, backp, "", "pre ");
            VNRelinker relinkHandle;
            nodep->unlinkFrBack(&relinkHandle);
            AstCCall* const callp = createDeepFunc(nodep);
            AstCFunc* const funcp = callp->funcp();
            {
                VL_RESTORER(m_deepFunc);
                m_deepFunc = true;
                iterate(funcp);
            }
            // Pass the local variables it references once the blocks in it are split, so each
            // statement is scanned only for the innermost new function
            if (V3Outline::passLocals(funcp, callp)) {
                funcp->rtnType("VlCoroutine");
                relinkHandle.relink(new AstCAwait{callp->fileline(), callp});
            } else {
                relinkHandle.relink(callp->makeStmt());
            }
            UINFOTREE(9, backp, "", "post");
            UINFOTREE(9, funcp, "", "func");
        } else {
            iterateChildren(nodep);
        }
        --m_depth;
    }

    void visit(AstNodeExpr*) override {}  // Accelerate
    //--------------------
    void visit(AstVar*) override {}  // Don't hit varrefs under vars
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit DepthBlockVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~DepthBlockVisitor() override = default;
};

//######################################################################
// DepthBlock class functions

void V3DepthBlock::depthBlockAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { DepthBlockVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("deepblock", 0, dumpTreeEitherLevel() >= 3);
}
