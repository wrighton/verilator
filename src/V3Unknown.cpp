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
// V3Unknown's Transformations:
//
// Each module:
//   UnknownVisitor:
//      TBD: Eliminate tristates by adding __in, __inen, __en wires in parallel
//          Need __en in changed list if a signal is on the LHS of a assign
//      Constants:
//          RHS, Replace 5'bx_1_x with a module global we init to a random value
//              CONST(5'bx_1_x) -> VARREF(_{numberedtemp})
//                              -> VAR(_{numberedtemp})
//                              -> INITIAL(VARREF(_{numberedtemp}),
//                                         OR(5'bx_1_x,AND(random,5'b0_1_x))
//              OPTIMIZE: Must not collapse this initial back into the equation.
//
//   KnownVisitor:
//      Variables and expressions:
//          If is of a four-state dtype replace it with a two-state counterpart
//      Complex dtypes:
//          Substitute four-state subDTypes with their two-state counterpart
//
// Post V3Unknown phase there should be no four-state constructs in an AST
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Unknown.h"

#include "V3Const.h"
#include "V3Stats.h"
#include "V3Timing.h"
#include "V3UniqueNames.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################

uint64_t V3Unknown::staticMax(const AstNodeExpr* exprp) {
    const uint64_t widthMax = exprp->width() < VL_QUADSIZE ? (1ULL << exprp->width()) - 1
                                                           : std::numeric_limits<uint64_t>::max();
    // Arithmetic that may exceed the width wraps, so only the width bounds it
    const auto bounded = [widthMax](uint64_t value, bool overflow) {
        return overflow ? widthMax : std::min(value, widthMax);
    };
    if (const AstConst* const constp = VN_CAST(exprp, Const)) {
        const V3Number& num = constp->num();
        if (!num.isFourState() && num.width() <= VL_QUADSIZE) return num.toUQuad();
    } else if (const AstAnd* const andp = VN_CAST(exprp, And)) {
        return std::min(V3Unknown::staticMax(andp->lhsp()), V3Unknown::staticMax(andp->rhsp()));
    } else if (const AstCond* const condp = VN_CAST(exprp, Cond)) {
        return std::max(V3Unknown::staticMax(condp->thenp()),
                        V3Unknown::staticMax(condp->elsep()));
    } else if (const AstExtend* const extendp = VN_CAST(exprp, Extend)) {
        return V3Unknown::staticMax(extendp->lhsp());
    } else if (const AstExtendS* const extendp = VN_CAST(exprp, ExtendS)) {
        // Unchanged unless its sign bit may be set
        const uint64_t lhs = V3Unknown::staticMax(extendp->lhsp());
        const int lhsWidth = extendp->lhsp()->width();
        if (lhsWidth <= VL_QUADSIZE && lhs < (1ULL << (lhsWidth - 1))) return lhs;
    } else if (const AstAdd* const addp = VN_CAST(exprp, Add)) {
        const uint64_t lhs = V3Unknown::staticMax(addp->lhsp());
        const uint64_t rhs = V3Unknown::staticMax(addp->rhsp());
        return bounded(lhs + rhs, lhs + rhs < lhs);
    } else if (const AstMul* const mulp = VN_CAST(exprp, Mul)) {
        const uint64_t lhs = V3Unknown::staticMax(mulp->lhsp());
        const uint64_t rhs = V3Unknown::staticMax(mulp->rhsp());
        return bounded(lhs * rhs, lhs != 0 && rhs > widthMax / lhs);
    } else if (const AstShiftL* const shiftp = VN_CAST(exprp, ShiftL)) {
        const uint64_t lhs = V3Unknown::staticMax(shiftp->lhsp());
        const uint64_t shift = V3Unknown::staticMax(shiftp->rhsp());
        if (shift >= VL_QUADSIZE) return widthMax;
        return bounded(lhs << shift, lhs > (widthMax >> shift));
    }
    return widthMax;
}

//######################################################################

class UnknownVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared on Netlist
    //  AstSel::user()          -> bool.  Set true if already processed
    //  AstArraySel::user()     -> bool.  Set true if already processed
    //  AstCond::user()         -> bool.  Set true if guarding a select
    //  AstNode::user2p()       -> AstIf* Inserted if assignment for conditional
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;
    static const std::string s_xrandPrefix;
    // Most nodes of a position containing a guarded select that is copied, not evaluated once.
    // A guarded bit or element select of a variable index is about 10 to 20 nodes, so one level
    // of nesting is copied and stays visible to Gate and Dfg, while deeper nesting, whose copies
    // would multiply at each level, is evaluated once.
    static constexpr int MAX_COPIED_NODES = 32;

    // STATE - across all visitors
    VDouble0 m_statUnkVars;  // Statistic of xrand variable created
    VDouble0 m_statElses;  // Statistic of else branches created for array selects
    V3UniqueNames m_lvboundNames;  // For generating unique temporary variable names
    std::unique_ptr<V3UniqueNames> m_xrandNames;  // For generating unique temporary variable names

    // STATE - for current visit position (use VL_RESTORER)
    AstNodeModule* m_modp = nullptr;  // Current module
    AstNodeFTask* m_ftaskp = nullptr;  // Current function/task
    bool m_constXCvt = false;  // Convert X's
    bool m_allowXUnique = true;  // Allow unique assignments

    // METHODS

    void addVar(AstVar* varp) {
        if (m_ftaskp) {
            varp->funcLocal(true);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_ftaskp->prependDeclsp(varp);
        } else {
            m_modp->prependStmtsp(varp);
        }
    }

    // Evaluate the value of blocking 'assignp' into a temporary before its intra-assignment
    // timing control, which then holds the assignment, as V3Timing does. The target is selected
    // when the wait ends (IEEE 1800-2023 9.4.5).
    void factorOutTimingControl(AstAssign* assignp) {
        FileLine* const fl = assignp->fileline();
        AstNodeExpr* const rhsp = assignp->rhsp();
        AstVar* const varp
            = new AstVar{fl, VVarType::MODULETEMP, m_lvboundNames.get(rhsp), rhsp->dtypep()};
        addVar(varp);
        rhsp->replaceWith(new AstVarRef{fl, varp, VAccess::READ});
        assignp->addHereThisAsNext(
            new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE}, rhsp});
        V3Timing::factorOutTimingControl(assignp);
    }
    // Whether 'nodep' is in the target of 'assignp'
    static bool inTarget(const AstNode* nodep, const AstNodeAssign* assignp) {
        for (; nodep != assignp; nodep = nodep->firstAbovep()) {
            if (nodep == assignp->lhsp()) return true;
        }
        return false;
    }

    void replaceBoundLvalue(AstNodeExpr* nodep, AstNodeExpr* condp) {
        // Spec says a out-of-range LHS SEL results in a NOP.
        // We wrap the expression into IF
        AstNodeExpr* prep = nodep;

        // Scan back to put the condlvalue above all selects (IE top of the lvalue)
        while (VN_IS(prep->backp(), NodeSel) || VN_IS(prep->backp(), Sel)
               || VN_IS(prep->backp(), MemberRef) || VN_IS(prep->backp(), StructSel)) {
            prep = VN_AS(prep->backp(), NodeExpr);
        }
        if (VN_IS(prep->backp(), AssignForce) || VN_IS(prep->backp(), Release)) {
            if (condp->isZero()) {
                // Forcing or releasing only bits out of range does nothing (IEEE 1800-2023 11.5.1)
                AstNode* const stmtp = prep->backp()->unlinkFrBack();
                VL_DO_DANGLING(pushDeletep(stmtp), stmtp);
                VL_DO_DANGLING(condp->deleteTree(), condp);
                return;
            }
            // The conversion done in this function breaks force and release statements
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: Force / release statement with complex select expression");
            VL_DO_DANGLING(condp->deleteTree(), condp);
            return;
        }
        FileLine* const fl = nodep->fileline();
        VL_DANGLING(nodep);  // Zap it so we don't use it by mistake - use prep

        // Already exists; rather than IF(a,... IF(b... optimize to IF(a&&b,
        // Saves us teaching V3Const how to optimize, and it won't be needed again.
        if (const AstIf* const ifp = VN_AS(prep->user2p(), If)) {
            VNRelinker replaceHandle;
            AstNodeExpr* const earliercondp = ifp->condp()->unlinkFrBack(&replaceHandle);
            AstNodeExpr* const newp = new AstLogAnd{condp->fileline(), condp, earliercondp};
            UINFO(4, "Edit BOUNDLVALUE " << newp);
            replaceHandle.relink(newp);
        } else {
            AstNodeStmt* stmtp = nullptr;  // Grab above point before we replace 'prep'
            for (AstNode* abovep = prep->backp(); !stmtp; abovep = abovep->backp()) {
                stmtp = VN_CAST(abovep, NodeStmt);
            }
            // A blocking assignment checks its target when its timing control ends; a select in
            // its value guards the whole statement, as the value is evaluated before
            if (AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
                if (assignp->timingControlp() && inTarget(prep, assignp)) {
                    factorOutTimingControl(assignp);
                }
            }
            VNRelinker replaceHandle;
            AstNodeStmt* const origStmtp = stmtp->unlinkFrBack(&replaceHandle);
            AstNodeStmt* elseStmtp = nullptr;
            const bool hasSideEffects = origStmtp->exists(
                [](AstNode* const np) { return !np->isPure() || np->isTimingControl(); });
            if (hasSideEffects) {
                // Copy original statement and replace `prep` with reference to tmp var to make
                // sure that side effect will take place
                ++m_statElses;
                elseStmtp = origStmtp->cloneTree(false);
                AstVar* const varp = new AstVar{fl, VVarType::MODULETEMP, m_lvboundNames.get(prep),
                                                prep->dtypep()};
                addVar(varp);
                AstNode* const prepCopyp = prep->clonep();
                // As written by the original, e.g. read-write as a library call's inout argument
                prepCopyp->replaceWith(new AstVarRef{fl, varp, prep->getVAccessRecurse()});
                VL_DO_DANGLING(pushDeletep(prepCopyp), prepCopyp);
                // Start from the default value (IEEE 1800-2023 7.4.6), not what an earlier
                // execution left, as an inout argument reads it, and push_back() extends it
                elseStmtp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                    new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                  new AstCReset{fl, varp, false}},
                    elseStmtp);
            }
            AstIf* const newp = new AstIf{fl, condp, origStmtp, elseStmtp};
            replaceHandle.relink(newp);
            newp->branchPred(VBranchPred::BP_LIKELY);
            newp->isBoundsCheck(true);
            prep->user2p(newp);  // Save so we may LogAnd it next time
        }
    }

    AstVar* createAddTemp(const AstNodeExpr* const nodep) {
        AstVar* const varp = new AstVar{nodep->fileline(), VVarType::XTEMP,
                                        m_xrandNames->get(nodep), nodep->dtypep()};
        addVar(varp);
        return varp;
    }

    // Return position 'bitp' truncated to the bits that address 'elements' bits, after its
    // bounds check, as V3Width keeps all its bits for that check
    static AstNodeExpr* newIndexTrunc(AstNodeExpr* bitp, int elements) {
        const int width = V3Number::log2b(elements - 1) + 1;
        if (bitp->width() <= width) return bitp;
        return V3Const::constifyEdit(new AstSel{bitp->fileline(), bitp, 0, width});
    }

    // Return a reference to a new temporary, replacing 'exprp' with an assignment to it
    AstVarRef* newExprStmtTemp(AstNodeExpr*& exprp) {
        AstVar* const varp = createAddTemp(exprp);
        FileLine* const flp = exprp->fileline();
        exprp = new AstExprStmt{
            flp, new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE}, exprp},
            new AstVarRef{flp, varp, VAccess::READ}};
        return new AstVarRef{flp, varp, VAccess::READ};
    }

    // Whether 'exprp' is costly to copy: large, and containing a select guarded by this pass, as
    // in nested selects, whose copies would multiply. A temporary for a cheaper one would hide
    // it from later optimizations.
    static bool costlyToCopy(const AstNodeExpr* exprp) {
        return exprp->isLargerThan(MAX_COPIED_NODES)
               && exprp->exists([](const AstCond* condp) { return condp->user1(); });
    }
    // Return a copy of 'exprp' to use after it, or if it is not repeatable or 'once', a
    // temporary that 'exprp' becomes an assignment to
    AstNodeExpr* newExprStmtOrClone(AstNodeExpr*& exprp, bool once = false) {
        // A clone evaluates the expression again
        if (once || !exprp->isRepeatable()) return newExprStmtTemp(exprp);
        return exprp->cloneTreePure(false);
    }
    // If the value 'fromp' a select reads is impure, such as a method's result, make it a
    // temporary, so it is evaluated once whatever the position; return the assignment to it
    AstNodeStmt* newImpureValueAssign(AstNodeExpr* fromp) {
        if (fromp->isRepeatable()) return nullptr;
        FileLine* const fl = fromp->fileline();
        VNRelinker relinker;
        fromp->unlinkFrBack(&relinker);
        AstVar* const varp = createAddTemp(fromp);
        relinker.relink(new AstVarRef{fl, varp, VAccess::READ});
        return new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE}, fromp};
    }
    // Return 'exprp' evaluated after statements 'stmtsp', if any, through a temporary, as a
    // wide value could otherwise be computed before them
    AstNodeExpr* newAfterStmts(AstNodeStmt* stmtsp, AstNodeExpr* exprp) {
        if (!stmtsp) return exprp;
        FileLine* const fl = exprp->fileline();
        AstVar* const varp = createAddTemp(exprp);
        stmtsp->addNext(new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE}, exprp});
        return new AstExprStmt{fl, stmtsp, new AstVarRef{fl, varp, VAccess::READ}};
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        UINFO(4, " MOD   " << nodep);
        VL_RESTORER(m_modp);
        VL_RESTORER(m_constXCvt);
        VL_RESTORER(m_allowXUnique);
        auto xrandNames = std::make_unique<V3UniqueNames>(s_xrandPrefix);
        {
            m_modp = nodep;
            m_constXCvt = true;
            // Class X randomization causes Vxrand in strange places, so disable
            if (VN_IS(nodep, Class)) m_allowXUnique = false;
            m_lvboundNames.reset();
            xrandNames.swap(m_xrandNames);
            iterateChildren(nodep);
            xrandNames.swap(m_xrandNames);
        }
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_ftaskp);
        m_ftaskp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstCaseItem* nodep) override {
        VL_RESTORER(m_constXCvt);
        m_constXCvt = false;  // Avoid losing the X's in casex
        iterateAndNextNull(nodep->condsp());
        m_constXCvt = true;
        iterateAndNextNull(nodep->stmtsp());
    }
    void visit(AstNodeDType* nodep) override {
        VL_RESTORER(m_constXCvt);
        m_constXCvt = false;  // Avoid losing the X's in casex
        iterateChildren(nodep);
    }
    void visit(AstVar* nodep) override {
        VL_RESTORER(m_allowXUnique);
        if (nodep->isParam() || nodep->constPoolEntry()) m_allowXUnique = false;
        iterateChildren(nodep);
    }
    void visitEqNeqCase(AstNodeBiop* nodep) {
        UINFO(4, " N/EQCASE->EQ " << nodep);
        V3Const::constifyEdit(nodep->lhsp());  // lhsp may change
        V3Const::constifyEdit(nodep->rhsp());  // rhsp may change
        if (VN_IS(nodep->lhsp(), Const) && VN_IS(nodep->rhsp(), Const)) {
            // Both sides are constant, node can be constant
            VL_DO_DANGLING(V3Const::constifyEdit(nodep), nodep);
            return;
        } else {
            AstNodeExpr* const lhsp = nodep->lhsp()->unlinkFrBack();
            AstNodeExpr* const rhsp = nodep->rhsp()->unlinkFrBack();
            AstNodeExpr* newp;
            // If we got ==1'bx it can never be true (but 1'bx==1'bx can be!)
            if (((VN_IS(lhsp, Const) && VN_AS(lhsp, Const)->num().isFourState())
                 || (VN_IS(rhsp, Const) && VN_AS(rhsp, Const)->num().isFourState()))) {
                newp = new AstConst(nodep->fileline(), AstConst::WidthedValue{}, 1,
                                    (VN_IS(nodep, EqCase) ? 0 : 1));
                VL_DO_DANGLING(lhsp->deleteTree(), lhsp);
                VL_DO_DANGLING(rhsp->deleteTree(), rhsp);
            } else {
                if (VN_IS(nodep, EqCase)) {
                    newp = new AstEq{nodep->fileline(), lhsp, rhsp};
                } else {
                    newp = new AstNeq{nodep->fileline(), lhsp, rhsp};
                }
            }
            nodep->replaceWith(newp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            // Iterate tree now that we may have gotten rid of Xs
            iterateChildren(newp);
        }
    }
    void visitEqNeqWild(AstNodeBiop* nodep) {
        UINFO(4, " N/EQWILD->EQ " << nodep);
        V3Const::constifyEdit(nodep->lhsp());  // lhsp may change
        V3Const::constifyEdit(nodep->rhsp());  // rhsp may change
        if (VN_IS(nodep->lhsp(), Const) && VN_IS(nodep->rhsp(), Const)) {
            // Both sides are constant, node can be constant
            VL_DO_DANGLING(V3Const::constifyEdit(nodep), nodep);
            return;
        } else {
            AstNodeExpr* const lhsp = nodep->lhsp()->unlinkFrBack();
            AstNodeExpr* const rhsp = nodep->rhsp()->unlinkFrBack();
            AstNodeExpr* newp;
            if (!VN_IS(rhsp, Const)) {
                if (rhsp->dtypep()->isFourstate()) {
                    nodep->v3warn(
                        E_UNSUPPORTED,
                        "Unsupported: RHS of ==? or !=? is fourstate but not a constant");
                }
                newp = new AstEq{nodep->fileline(), lhsp, rhsp};
            } else {
                // X or Z's become mask, ala case statements.
                V3Number nummask{rhsp, rhsp->width()};
                nummask.opBitsNonXZ(VN_AS(rhsp, Const)->num());
                V3Number numval{rhsp, rhsp->width()};
                numval.opBitsOne(VN_AS(rhsp, Const)->num());
                AstNodeExpr* const and1p = new AstAnd{nodep->fileline(), lhsp,
                                                      new AstConst{nodep->fileline(), nummask}};
                AstNodeExpr* const and2p = new AstConst{nodep->fileline(), numval};
                if (VN_IS(nodep, EqWild)) {
                    newp = new AstEq{nodep->fileline(), and1p, and2p};
                } else {
                    newp = new AstNeq{nodep->fileline(), and1p, and2p};
                }
                VL_DO_DANGLING(rhsp->deleteTree(), rhsp);
            }
            nodep->replaceWith(newp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            // Iterate tree now that we may have gotten rid of the compare
            iterateChildren(newp);
        }
    }

    void visit(AstEqCase* nodep) override { visitEqNeqCase(nodep); }
    void visit(AstNeqCase* nodep) override { visitEqNeqCase(nodep); }
    void visit(AstEqWild* nodep) override { visitEqNeqWild(nodep); }
    void visit(AstNeqWild* nodep) override { visitEqNeqWild(nodep); }
    void visit(AstIsUnknown* nodep) override {
        iterateChildren(nodep);
        // Ahh, we're two state, so this is easy
        UINFO(4, " ISUNKNOWN->0 " << nodep);
        AstConst* const newp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
        nodep->replaceWith(newp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstCountBits* nodep) override {
        // Ahh, we're two state, so this is easy
        std::array<bool, 3> dropop;
        dropop[0] = VN_IS(nodep->rhsp(), Const) && VN_AS(nodep->rhsp(), Const)->num().isAnyX();
        dropop[1] = VN_IS(nodep->thsp(), Const) && VN_AS(nodep->thsp(), Const)->num().isAnyX();
        dropop[2] = VN_IS(nodep->fhsp(), Const) && VN_AS(nodep->fhsp(), Const)->num().isAnyX();
        UINFO(4, " COUNTBITS(" << dropop[0] << dropop[1] << dropop[2] << " " << nodep);

        AstNodeExpr* nonXp = nullptr;
        if (!dropop[0]) {
            nonXp = nodep->rhsp();
        } else if (!dropop[1]) {
            nonXp = nodep->thsp();
        } else if (!dropop[2]) {
            nonXp = nodep->fhsp();
        } else {  // Was all X-s
            UINFO(4, " COUNTBITS('x)->0 " << nodep);
            AstConst* const newp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
            nodep->replaceWith(newp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }
        if (dropop[0]) {
            nodep->rhsp()->unlinkFrBack()->deleteTree();
            nodep->rhsp(nonXp->cloneTreePure(true));
        }
        if (dropop[1]) {
            nodep->thsp()->unlinkFrBack()->deleteTree();
            nodep->thsp(nonXp->cloneTreePure(true));
        }
        if (dropop[2]) {
            nodep->fhsp()->unlinkFrBack()->deleteTree();
            nodep->fhsp(nonXp->cloneTreePure(true));
        }
        iterateChildren(nodep);
    }
    void visit(AstConst* nodep) override {
        if (m_constXCvt && nodep->num().isFourState()) {
            UINFO(4, " CONST4 " << nodep);
            UINFOTREE(9, nodep, "", "Const_old");
            // CONST(num) -> VARREF(newvarp)
            //          -> VAR(newvarp)
            //          -> INITIAL(VARREF(newvarp, OR(num_No_Xs,AND(random,num_1s_Where_X))
            V3Number numb1{nodep, nodep->width()};
            numb1.opBitsOne(nodep->num());
            V3Number numbx{nodep, nodep->width()};
            numbx.opBitsXZ(nodep->num());
            if (!m_allowXUnique || v3Global.opt.xAssign() != "unique") {
                // All X bits just become 0; fastest simulation, but not nice
                V3Number numnew{nodep, numb1.width()};
                if (v3Global.opt.xAssign() == "1") {
                    numnew.opOr(numb1, numbx);
                } else {
                    numnew.opAssign(numb1);
                }
                AstConst* const newp = new AstConst{nodep->fileline(), numnew};
                nodep->replaceWith(newp);
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
                UINFO(4, "   -> " << newp);
            } else {
                // Make a Vxrand variable
                // We use the special XTEMP type so it doesn't break pure functions
                UASSERT_OBJ(m_modp, nodep, "X number not under module");
                AstVar* const newvarp
                    = new AstVar{nodep->fileline(), VVarType::XTEMP, m_xrandNames->get(nullptr),
                                 VFlagLogicPacked{}, nodep->width()};
                newvarp->lifetime(VLifetime::STATIC_EXPLICIT);
                ++m_statUnkVars;
                VNRelinker replaceHandle;
                nodep->unlinkFrBack(&replaceHandle);
                AstNodeVarRef* const newref1p
                    = new AstVarRef{nodep->fileline(), newvarp, VAccess::READ};
                replaceHandle.relink(newref1p);  // Replace const with varref
                AstInitial* const newinitp = new AstInitial{
                    nodep->fileline(),
                    new AstAssign{
                        nodep->fileline(),
                        new AstVarRef{nodep->fileline(), newvarp, VAccess::WRITE},
                        new AstOr{nodep->fileline(), new AstConst{nodep->fileline(), numb1},
                                  new AstAnd{
                                      nodep->fileline(), new AstConst{nodep->fileline(), numbx},
                                      new AstVarRef{nodep->fileline(), newvarp, VAccess::READ}}}}};
                // Add inits in front of other statement.
                // In the future, we should stuff the initp into the module's constructor.
                // Must not unlink the statements, as one of them is being iterated
                AstNode* const newStmtsp = AstNode::addNext<AstNode, AstNode>(newvarp, newinitp);
                m_modp->prependStmtsp(newStmtsp);
                UINFOTREE(9, newref1p, "", "_newref");
                UINFOTREE(9, newvarp, "", "_newvar");
                UINFOTREE(9, newinitp, "", "_newini");
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
            }
        }
    }

    void visit(AstSel* nodep) override {
        iterateChildren(nodep);
        if (!nodep->user1SetOnce()) {
            // Guard against reading/writing past end of bit vector array
            // Not a select of a method's result, such as a queue's popped element, though the
            // method writes its object
            const bool lvalue = nodep->isLValue();
            // Find range of dtype we are selecting from
            // Similar code in V3Const::warnSelect
            // Reading the padding of a value narrower than the selection is as reading out of
            // range
            const int valueWidth = nodep->valueWidth() && !lvalue
                                       ? nodep->valueWidth()
                                       : nodep->fromp()->dtypep()->width();
            const uint32_t maxmsb = valueWidth - 1;
            UINFOTREE(9, nodep, "", "sel_old");

            // If (maxmsb >= selected), we're in bound
            // See if the condition is constant true (e.g. always in bound due to constant select)
            // Note below has null backp(); the Edit function knows how to deal with that.
            AstConst* const maxmsbConstp = new AstConst{
                nodep->fileline(), AstConst::WidthedValue{}, nodep->lsbp()->width(), maxmsb};
            AstNodeExpr* lsbp = V3Const::constifyEdit(nodep->lsbp()->unlinkFrBack());
            if (maxmsb + 1 >= static_cast<uint32_t>(nodep->widthConst())
                && V3Unknown::staticMax(lsbp) <= maxmsb + 1 - nodep->widthConst()) {
                // We don't need to add a conditional; the whole selection is in range
                VL_DO_DANGLING(maxmsbConstp->deleteTree(), maxmsbConstp);
                nodep->lsbp(newIndexTrunc(lsbp, maxmsb + 1));
                return;
            }
            // A position costly to copy is evaluated once, as it is used twice
            nodep->lsbp(newIndexTrunc(newExprStmtOrClone(lsbp, costlyToCopy(lsbp)), maxmsb + 1));
            AstNodeExpr* condp
                = V3Const::constifyEdit(new AstGte{nodep->fileline(), maxmsbConstp, lsbp});
            if (condp->isNeqZero()) {
                // The position is in range, which is all this checks
                VL_DO_DANGLING(condp->deleteTree(), condp);
                return;
            }
            if (!lvalue) {
                // SEL(...) -> COND(LTE(bit<=maxmsb), ARRAYSEL(...), {width{1'bx}})
                VNRelinker replaceHandle;
                nodep->unlinkFrBack(&replaceHandle);
                AstNodeStmt* const fromAssignp = newImpureValueAssign(nodep->fromp());
                V3Number xnum{nodep, nodep->width()};
                // Bits of a 2-state vector read as zero (IEEE 1800-2023 11.5.1)
                // As the select's own type: the value may be an X, of a lower select out of
                // range, already replaced by a 2-state constant
                if (nodep->dtypep()->isFourstate()) xnum.setAllBitsX();
                AstNodeExpr* const xexprp = new AstConst{nodep->fileline(), xnum};
                AstNodeExpr* const newp = [&]() -> AstNodeExpr* {
                    if (condp->isZero()) {
                        VL_DO_DANGLING(condp->deleteTree(), condp);
                        VL_DO_DANGLING(nodep->deleteTree(), nodep);
                        return xexprp;
                    }
                    AstCond* const guardp = new AstCond{nodep->fileline(), condp, nodep, xexprp};
                    guardp->user1(true);
                    return guardp;
                }();
                UINFOTREE(9, newp, "", "_new");
                // Link in conditional
                replaceHandle.relink(newAfterStmts(fromAssignp, newp));
                // Added X's, tristate them too
                iterate(newp);
            } else {  // lvalue
                replaceBoundLvalue(nodep, condp);
            }
        }
    }

    // visit(AstSliceSel) not needed as its bounds are constant and checked
    // in V3Width.

    void visit(AstArraySel* nodep) override {
        iterateChildren(nodep);
        if (!nodep->user1SetOnce()) {
            UINFOTREE(9, nodep, "", "in");
            // Guard against reading/writing past end of arrays
            // Not a select of a method's result, such as a queue's popped element, though the
            // method writes its object
            const bool lvalue = nodep->isLValue();
            // Find range of dtype we are selecting from
            int declElements = -1;
            AstNodeDType* const dtypep = nodep->fromp()->dtypep()->skipRefp();
            UASSERT_OBJ(dtypep, nodep, "Select of non-selectable type");
            const AstNodeArrayDType* const adtypep = VN_CAST(dtypep, NodeArrayDType);
            UASSERT_OBJ(adtypep, nodep, "Select from non-array " << dtypep->prettyTypeNameQ());
            declElements = adtypep->elementsConst();
            UINFOTREE(9, nodep, "", "arraysel_old");

            // If value MODDIV constant, where constant <= declElements, known ok
            // V3Random makes these to intentionally prevent exceeding enum array bounds.
            if (const AstModDiv* const moddivp = VN_CAST(nodep->bitp(), ModDiv)) {
                if (const AstConst* const modconstp = VN_CAST(moddivp->rhsp(), Const)) {
                    if (modconstp->width() <= 32
                        && modconstp->toUInt() <= static_cast<uint32_t>(declElements)) {
                        UINFO(9, "arraysel mod const " << declElements
                                                       << " >= " << modconstp->toUInt());
                        return;
                    }
                }
            }

            // See if the condition is constant true
            AstConst* const declElementsp
                = new AstConst{nodep->fileline(), AstConst::WidthedValue{}, nodep->bitp()->width(),
                               static_cast<uint32_t>(declElements - 1)};
            AstNodeExpr* bitp = V3Const::constifyEdit(nodep->bitp()->unlinkFrBack());
            if (V3Unknown::staticMax(bitp) <= static_cast<uint64_t>(declElements - 1)) {
                // We don't need to add a conditional; we know the existing expression is ok
                VL_DO_DANGLING(declElementsp->deleteTree(), declElementsp);
                nodep->bitp(bitp);
                return;
            }
            nodep->bitp(newExprStmtOrClone(bitp));
            AstNodeExpr* condp = new AstGte{nodep->fileline(), declElementsp, bitp};
            // Note below has null backp(); the Edit function knows how to deal with that.
            const AstNodeDType* const nodeDtp = nodep->dtypep()->skipRefp();
            if (!lvalue
                // Making a scalar would break if we're making an array; an element of a packed
                // type reads its default, not element zero (IEEE 1800-2023 7.4.6)
                && (VN_IS(nodeDtp, BasicDType) || nodeDtp->isIntegralOrPacked())) {
                // ARRAYSEL(...) -> COND(LT(bit<maxbit), ARRAYSEL(...), {width{1'bx}})
                VNRelinker replaceHandle;
                nodep->unlinkFrBack(&replaceHandle);
                FileLine* const fl = nodep->fileline();
                AstNodeExpr* valuep = nodep;
                AstNodeStmt* stmtsp = nullptr;
                if (!nodep->fromp()->isRepeatable()) {
                    // An impure array, such as a method's result, is selected from at an index
                    // kept in range, so is evaluated whatever the index
                    AstVar* const inRangep = createAddTemp(condp);
                    stmtsp = new AstAssign{fl, new AstVarRef{fl, inRangep, VAccess::WRITE}, condp};
                    AstNodeExpr* const indexp = nodep->bitp()->unlinkFrBack();
                    nodep->bitp(new AstCond{
                        fl, new AstVarRef{fl, inRangep, VAccess::READ}, indexp,
                        new AstConst{fl, AstConst::WidthedValue{}, indexp->width(), 0}});
                    AstVar* const elementp = createAddTemp(nodep);
                    stmtsp->addNext(
                        new AstAssign{fl, new AstVarRef{fl, elementp, VAccess::WRITE}, nodep});
                    condp = new AstVarRef{fl, inRangep, VAccess::READ};
                    valuep = new AstVarRef{fl, elementp, VAccess::READ};
                }
                // TODO make a tieoff function that takes AstNode and returns typed value
                V3Number xnum{nodep, nodep->width()};
                if (nodeDtp->isDouble()) {
                    xnum = V3Number{nodep, V3Number::Double{}, 0.0};
                } else if (nodeDtp->isString()) {
                    xnum = V3Number{nodep, V3Number::String{}, ""};
                } else {
                    if (nodeDtp->isFourstate()) {
                        xnum.setAllBitsX();
                    } else {
                        xnum.setAllBits0();
                    }
                }
                AstCond* const newp = new AstCond{fl, condp, valuep, new AstConst{fl, xnum}};
                newp->user1(true);
                UINFOTREE(9, newp, "", "_new");
                // Link in conditional, can blow away temp xor
                replaceHandle.relink(newAfterStmts(stmtsp, newp));
                // Added X's, tristate them too
                iterate(newp);
            } else if (!lvalue) {  // Mid-multidimension read, just use zero
                // ARRAYSEL(...) -> ARRAYSEL(COND(LT(bit<maxbit), bit, 0))
                VNRelinker replaceHandle;
                AstNodeExpr* const asBitp = nodep->bitp()->unlinkFrBack(&replaceHandle);
                AstNodeExpr* const newp
                    = new AstCond{asBitp->fileline(), condp, asBitp,
                                  new AstConst{asBitp->fileline(), AstConst::WidthedValue{},
                                               asBitp->width(), 0}};
                newp->user1(true);
                // Added X's, tristate them too
                UINFOTREE(9, newp, "", "_new");
                replaceHandle.relink(newp);
                iterate(newp);
            } else {  // lvalue
                replaceBoundLvalue(nodep, condp);
            }
        }
    }
    //--------------------
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit UnknownVisitor(AstNetlist* nodep)
        : m_lvboundNames{"__Vlvbound"}
        , m_xrandNames{std::make_unique<V3UniqueNames>(s_xrandPrefix)} {
        iterate(nodep);
    }
    ~UnknownVisitor() override {  //
        V3Stats::addStat("Unknowns, variables created", m_statUnkVars);
        V3Stats::addStat("Unknowns, else branches created", m_statElses);
    }
};

const std::string UnknownVisitor::s_xrandPrefix = "__Vxrand";

//######################################################################
// Known visitor

class KnownVisitor final : public VNVisitor {
    static AstNodeDType* dtypepToTwostate(AstNodeDType* const dtypep) {
        if (AstEnumDType* const edtypep = VN_CAST(dtypep, EnumDType)) {
            if (AstEnumDType* const resultp = edtypep->originalDTypep()) return resultp;
        } else if (AstNodeUOrStructDType* const sdtypep = VN_CAST(dtypep, NodeUOrStructDType)) {
            if (AstNodeUOrStructDType* const resultp = sdtypep->originalDTypep()) return resultp;
        } else if (AstBasicDType* const basicp = VN_CAST(dtypep, BasicDType)) {
            if (basicp->isIntegralOrPacked()) return basicp->findStatesCounterpart(false);
        }
        return nullptr;
    }
    static void setTwostateIfAble(AstNode* const nodep) {
        if (AstNodeDType* const dtypep = dtypepToTwostate(nodep->dtypep())) {
            nodep->dtypep(dtypep);
        }
    }
    template <typename T>
    static void subDTypeUpdate(T* const nodep) {
        if (AstNodeDType* const dtypep = dtypepToTwostate(nodep->subDTypep())) {
            nodep->refDTypep(dtypep);
        }
    }

    // VISITORS
    // DTypes visitors
    void visit(AstNodeArrayDType* const nodep) override {
        subDTypeUpdate(nodep);
        iterateChildren(nodep);
    }
    void visit(AstAssocArrayDType* const nodep) override {
        subDTypeUpdate(nodep);
        if (AstNodeDType* const dtypep = dtypepToTwostate(nodep->keyDTypep())) {
            nodep->keyDTypep(dtypep);
        }
    }
    void visit(AstWildcardArrayDType* const nodep) override { subDTypeUpdate(nodep); }
    void visit(AstConstDType* const nodep) override { subDTypeUpdate(nodep); }
    void visit(AstQueueDType* const nodep) override {
        subDTypeUpdate(nodep);
        iterateChildren(nodep);
    }
    void visit(AstDynArrayDType* const nodep) override { subDTypeUpdate(nodep); }
    void visit(AstUnsizedArrayDType* const nodep) override { subDTypeUpdate(nodep); }
    void visit(AstSampleQueueDType* const nodep) override {
        if (AstNodeDType* const dtypep = dtypepToTwostate(nodep->subDTypep())) {
            nodep->refDTypep(dtypep);
            nodep->dtypep(dtypep);
        }
    }
    void visit(AstEnumDType* const nodep) override {
        subDTypeUpdate(nodep);
        iterateChildren(nodep);
    }
    void visit(AstNodeUOrStructDType* const nodep) override {
        if (nodep->isFourstate()) {
            nodep->mimicsFourstate(true);
            nodep->isFourstate(false);
            subDTypeUpdate(nodep);
        }
        iterateChildren(nodep);
    }
    void visit(AstMemberDType* const nodep) override {
        iterateChildren(nodep);
        if (AstNodeDType* const dtypep = dtypepToTwostate(nodep->subDTypep())) {
            nodep->refDTypep(dtypep);
            nodep->dtypep(dtypep);
        } else {
            setTwostateIfAble(nodep);
        }
    }
    void visit(AstRefDType* const nodep) override {
        if (AstNodeDType* const dtypep = nodep->refDTypep()) {
            if (AstNodeDType* const newp = dtypepToTwostate(dtypep)) nodep->refDTypep(newp);
        }
        nodep->dtypep(nodep->subDTypep());
    }
    void visit(AstParamTypeDType* const nodep) override { setTwostateIfAble(nodep); }
    void visit(AstTypedef* const nodep) override { setTwostateIfAble(nodep); }

    // Other visitors
    void visit(AstVar* const nodep) override {
        iterateChildren(nodep);
        setTwostateIfAble(nodep);
    }
    void visit(AstNodeExpr* const nodep) override {
        iterateChildren(nodep);
        setTwostateIfAble(nodep);
    }
    void visit(AstNodeAssign* const nodep) override {
        iterateChildren(nodep);
        nodep->dtypeFrom(nodep->lhsp());
    }
    void visit(AstWith* const nodep) override {
        iterateChildren(nodep);
        nodep->dtypeFrom(nodep->exprp());
    }
    void visit(AstFunc* const nodep) override {
        iterateChildren(nodep);
        if (const AstVar* const varp = nodep->fvarp()) nodep->dtypeFrom(varp);
    }
    void visit(AstNode* const nodep) override { iterateChildren(nodep); }

public:
    explicit KnownVisitor(AstNetlist* const netlistp) { iterate(netlistp); }
    ~KnownVisitor() override = default;
};

void V3Unknown::unknownAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { UnknownVisitor{nodep}; }  // Destruct before checking
    { KnownVisitor{nodep}; }
    v3Global.fourstateResolved(true);  // set fourstateResolved before checking
    V3Global::dumpCheckGlobalTree("unknown", 0, dumpTreeEitherLevel() >= 3);
}
