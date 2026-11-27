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

#include "V3UniqueNames.h"

AstVar* RandModeVars::randModeVarp(AstNodeModule* classp) {
    while (classp) {
        if (classp->user2p()) return VN_AS(classp->user2p(), Var);
        AstClass* const cp = VN_CAST(classp, Class);
        if (!cp || !cp->extendsp()) return nullptr;
        classp = cp->extendsp()->classp();
    }
    return nullptr;
}

AstNodeStmt* RandModeVars::wrapIfMode(const RandomizeMode mode, AstVar* modeVarp,
                                      AstNodeStmt* stmtp) {
    FileLine* const fl = stmtp->fileline();
    if (mode.usesMode) {
        // user2p can be either AstClass or AstClassPackage (for static constraints)
        AstNodeModule* const modp = VN_AS(modeVarp->user2p(), NodeModule);
        AstDynArraySel* const atp = new AstDynArraySel{
            fl, new AstVarRef{fl, modp, modeVarp, VAccess::READ}, new AstConst{fl, mode.index}};
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

//######################################################################
// V3SolverLowering

// Add to savesr the copies of the random variables of classp, of the object basep is, or of
// this if nullptr, and to restoresr the assignments back. A static member, shared by the
// objects of its class, is copied once (staticsr).
static void addRandomSaves(AstFunc* funcp, AstClass* classp, AstNodeExpr* basep,
                           V3UniqueNames& uniqueNames,
                           std::unordered_set<const AstClass*>& visitingr,
                           std::unordered_set<const AstVar*>& staticsr, AstNodeStmt*& savesr,
                           AstNodeStmt*& restoresr) {
    FileLine* const fl = funcp->fileline();
    visitingr.emplace(classp);
    classp->foreachMember([&](AstClass* memberClassp, AstVar* varp) {
        if (!varp->rand().isRandomizable()) return;
        const bool isStatic = varp->lifetime().isStatic();
        if (isStatic && !staticsr.emplace(varp).second) return;
        const auto refp = [&](VAccess access) -> AstNodeExpr* {
            if (!basep || isStatic) return new AstVarRef{fl, memberClassp, varp, access};
            AstMemberRef* const selp = new AstMemberRef{fl, basep->cloneTree(false), varp};
            selp->access(access);
            return selp;
        };
        // The objects of rand handles are kept too; the handles themselves randomize() does
        // not change
        const auto saveObject = [&](AstNodeExpr* const objp, AstClass* const objClassp) {
            if (!visitingr.count(objClassp)) {  // A cycle of handles is not followed
                AstNodeStmt* objSavesp = nullptr;
                AstNodeStmt* objRestoresp = nullptr;
                addRandomSaves(funcp, objClassp, objp, uniqueNames, visitingr, staticsr, objSavesp,
                               objRestoresp);
                const auto nonNullp = [&]() {
                    return new AstNeq{fl, objp->cloneTree(false),
                                      new AstConst{fl, AstConst::Null{}}};
                };
                if (objSavesp) {
                    savesr = AstNode::addNextNull(savesr, new AstIf{fl, nonNullp(), objSavesp});
                    restoresr
                        = AstNode::addNextNull(restoresr, new AstIf{fl, nonNullp(), objRestoresp});
                }
            }
            VL_DO_DANGLING(objp->deleteTree(), objp);
        };
        const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
        if (const AstClassRefDType* const objDTypep = VN_CAST(dtypep, ClassRefDType)) {
            saveObject(refp(VAccess::READ), objDTypep->classp());
            return;
        }
        // Of a fixed-size array of handles, each element's; those of a dynamic array or queue
        // of handles are not kept
        if (const AstUnpackArrayDType* const arrDTypep = VN_CAST(dtypep, UnpackArrayDType)) {
            if (const AstClassRefDType* const objDTypep
                = VN_CAST(arrDTypep->subDTypep()->skipRefp(), ClassRefDType)) {
                for (int i = 0; i < arrDTypep->elementsConst(); ++i) {
                    saveObject(new AstArraySel{fl, refp(VAccess::READ), i}, objDTypep->classp());
                }
                return;
            }
        }
        AstVar* const savep
            = new AstVar{fl, VVarType::BLOCKTEMP, uniqueNames.get("__Vsaved"), varp->dtypep()};
        savep->funcLocal(true);
        savep->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        funcp->addDeclsp(savep);
        savesr = AstNode::addNextNull(
            savesr,
            new AstAssign{fl, new AstVarRef{fl, savep, VAccess::WRITE}, refp(VAccess::READ)});
        restoresr = AstNode::addNextNull(
            restoresr,
            new AstAssign{fl, refp(VAccess::WRITE), new AstVarRef{fl, savep, VAccess::READ}});
    });
    visitingr.erase(classp);
}

AstNodeStmt* V3SolverLowering::addFailureRestore(AstFunc* funcp, AstClass* classp) {
    std::unordered_set<const AstClass*> visiting;
    std::unordered_set<const AstVar*> statics;
    AstNodeStmt* savesp = nullptr;
    AstNodeStmt* restoresp = nullptr;
    addRandomSaves(funcp, classp, nullptr, m_uniqueNames, visiting, statics, savesp, restoresp);
    if (savesp) funcp->addStmtsp(savesp);
    return restoresp;
}
