// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Interface between randomize() lowering and constraint solvers
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
// V3Randomize is split into a solver-neutral front end (V3Randomize.cpp) and
// a constraint solver back-end. The back-end for the run is a V3SolverBackend
// held by V3Global, which creates a V3SolverLowering for each V3Randomize pass.
//
// The front end owns pre/post_randomize callbacks, rand_mode/constraint_mode
// state, __VBasicRand (randomization of unconstrained variables), argument
// handling and the capture of inline 'with' expressions. A back-end owns
// everything emitted to solve the constraints of a randomize site: a class
// randomize(), a randomize() with {...}, a std::randomize() with {...} and a
// randomize(null). Each site is lowered by a single hook, which the front end
// calls at a fixed point of its own lowering.
//
// Contract between the front end and a back-end's V3SolverLowering:
//  * Input: the AST marked by RandomizeMarkVisitor (AstNodeExpr::user1() set
//    on expressions depending on a randomized variable), the constraint blocks
//    of the class, the rand_mode/constraint_mode state (RandomizeMode in
//    user1() of the variables and constraints, the mode arrays in
//    RandModeVars), and, for inline sites, the captured 'with' items.
//  * Variable ownership: __VBasicRand skips variables with AstVar::user3()
//    set. The front end sets it on variables named in a class's own
//    constraints; a back-end sets it on any other variable it assigns, before
//    the front end emits __VBasicRand for the class.
//  * Output: a site hook either returns the solver result for the front end
//    to combine with __VBasicRand, or for inline sites, where the order of
//    __VBasicRand against the solver call matters, assigns the function's
//    return value itself. All other statements go into the given function,
//    or into members the back-end creates.
//  * Constraint items are consumed: the front end deletes every AstConstraint
//    once all sites are lowered, so a back-end may unlink or rewrite items.
//  * A back-end runs within the V3Randomize pass, and may use the AstNode
//    user fields that pass documents.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3SolverBackend.h"

AstVar* RandModeVars::randModeVarp(AstNodeModule* classp) {
    while (classp) {
        if (classp->user2p()) return VN_AS(classp->user2p(), Var);
        AstClass* const cp = VN_CAST(classp, Class);
        if (!cp || !cp->extendsp()) return nullptr;
        classp = cp->extendsp()->classp();
    }
    return nullptr;
}

AstNode* RandModeVars::wrapIfMode(const RandomizeMode mode, AstVar* modeVarp, AstNode* stmtp) {
    FileLine* const fl = stmtp->fileline();
    if (mode.usesMode) {
        // user2p can be either AstClass or AstClassPackage (for static constraints)
        AstNodeModule* const modp = VN_AS(modeVarp->user2p(), NodeModule);
        AstCMethodHard* const atp
            = new AstCMethodHard{fl, new AstVarRef{fl, modp, modeVarp, VAccess::READ},
                                 VCMethod::ARRAY_AT, new AstConst{fl, mode.index}};
        atp->dtypeSetUInt32();
        return new AstIf{fl, atp, stmtp};
    }
    return stmtp;
}

AstVar* RandModeVars::staticConstraintModeVarp(AstClass* classp) const {
    const auto it = m_staticConstraintModeVars.find(classp);
    if (it != m_staticConstraintModeVars.end()) return it->second;
    if (AstClassExtends* const extendsp = classp->extendsp()) {
        return staticConstraintModeVarp(extendsp->classp());
    }
    return nullptr;
}

AstVar* RandModeVars::staticRandModeVarp(AstClass* classp) const {
    const auto it = m_staticRandModeVars.find(classp);
    if (it != m_staticRandModeVars.end()) return it->second;
    if (AstClassExtends* const extendsp = classp->extendsp()) {
        return staticRandModeVarp(extendsp->classp());
    }
    return nullptr;
}

AstVar* RandModeVars::constraintModeVarp(AstClass* classp) {
    if (classp->user4p()) return VN_AS(classp->user4p(), Var);
    if (AstClassExtends* const extendsp = classp->extendsp()) {
        return constraintModeVarp(extendsp->classp());
    }
    return nullptr;
}

AstVar* ElemRandModes::modeVarp(AstVar* arrVarp) {
    if (!m_arrays.count(arrVarp)) return nullptr;
    AstVar*& modeVarp = m_modeVars[arrVarp];
    if (modeVarp) return modeVarp;
    // Keyed by element offset, kept across resizes, holding 1 for the elements with
    // rand_mode off
    FileLine* const fl = arrVarp->fileline();
    if (!m_dtypep) {
        m_dtypep = new AstAssocArrayDType{fl, arrVarp->findBitDType(), arrVarp->findUInt32DType()};
        m_dtypep->dtypep(m_dtypep);
        v3Global.rootp()->typeTablep()->addTypesp(m_dtypep);
    }
    AstClass* const classp = VN_AS(arrVarp->user2p(), Class);
    modeVarp = new AstVar{fl, VVarType::MEMBER, "__Vrandmode__" + arrVarp->name(), m_dtypep};
    modeVarp->user2p(classp);
    classp->addMembersp(modeVarp);
    return modeVarp;
}

//######################################################################
// RandomizeUtil implementation

AstNodeDType* RandomizeUtil::arrayElementDTypep(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefToEnump();
    while (dtypep->isNonPackedArray()) dtypep = dtypep->subDTypep()->skipRefToEnump();
    return dtypep;
}

AstNodeExpr* RandomizeUtil::newElemOffsetp(FileLine* const fl, const AstVar* const arrVarp,
                                   AstNodeExpr* const idxp) {
    const AstUnpackArrayDType* const unpackDtp
        = VN_CAST(arrVarp->dtypep()->skipRefp(), UnpackArrayDType);
    if (!unpackDtp) return idxp;
    AstNodeExpr* const offsetp
        = new AstSub{fl, idxp, new AstConst{fl, static_cast<uint32_t>(unpackDtp->lo())}};
    offsetp->dtypeSetUInt32();
    return offsetp;
}

bool RandomizeUtil::isClassHandleArray(AstVar* varp) {
    return varp->dtypep()->skipRefp()->isNonPackedArray()
           && VN_IS(RandomizeUtil::arrayElementDTypep(varp->dtypep()), ClassRefDType);
}

bool RandomizeUtil::operandsRand(const AstNode* nodep) {
    return (nodep->op1p() && nodep->op1p()->user1()) || (nodep->op2p() && nodep->op2p()->user1())
           || (nodep->op3p() && nodep->op3p()->user1())
           || (nodep->op4p() && nodep->op4p()->user1());
}

AstNodeExpr* RandomizeUtil::randIndexSelp(AstNodeExpr* exprp,
                                  bool (*isRandIndexp)(const AstNodeExpr* indexp)) {
    // exprp is the select itself, or reached from it through member and element selects and
    // array methods, e.g. 'arr[idx].q.size()'. Each step is to the first operand, fromp.
    for (AstNodeExpr* curp = exprp;;) {
        AstNodeExpr* fromp;
        AstNodeExpr* indexp = nullptr;
        if (AstArraySel* const arraySelp = VN_CAST(curp, ArraySel)) {
            fromp = arraySelp->fromp();
            indexp = arraySelp->bitp();
        } else if (AstCMethodHard* const methodp = VN_CAST(curp, CMethodHard)) {
            fromp = methodp->fromp();
            if (methodp->method() == VCMethod::ARRAY_AT) indexp = methodp->pinsp();
        } else if (AstStructSel* const structSelp = VN_CAST(curp, StructSel)) {
            fromp = structSelp->fromp();
        } else if (AstMemberSel* const memberSelp = VN_CAST(curp, MemberSel)) {
            fromp = memberSelp->fromp();
        } else {
            return nullptr;
        }
        if (indexp && !fromp->user1() && isRandIndexp(indexp)) return curp;
        curp = fromp;
    }
}

AstNodeExpr* RandomizeUtil::newElemModeOffp(AstNodeExpr* const modesp, AstNodeExpr* const indexp) {
    AstCMethodHard* const atp = new AstCMethodHard{
        indexp->fileline(), modesp, VCMethod::ARRAY_AT, indexp->cloneTree(false)};
    atp->dtypeSetBit();
    return atp;
}

AstNodeExpr* RandomizeUtil::newMemberRefp(FileLine* const fl, AstNodeExpr* const objp,
                                  AstVar* const varp) {
    if (objp) return new AstMemberSel{fl, objp->cloneTreePure(false), varp};
    return new AstVarRef{fl, VN_AS(varp->user2p(), Class), varp, VAccess::READ};
}
