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
//    to assign, or for inline sites assigns the function's return value
//    itself. __VBasicRand runs only after a successful solve (IEEE 1800-2023
//    18.6.3), emitted by the back-end after any function-call solve rounds.
//    All other statements go into the given function, or into members the
//    back-end creates.
//  * Constraint items are consumed: the front end deletes every AstConstraint
//    once all sites are lowered, so a back-end may unlink or rewrite items.
//  * A back-end runs within the V3Randomize pass, and may use the AstNode
//    user fields that pass documents.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3SolverBackend.h"

#include <algorithm>
#include <functional>

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

AstNodeExpr* RandomizeUtil::newElemOffsetp(FileLine* const fl, const AstNodeDType* const arrDtp,
                                           AstNodeExpr* const idxp) {
    const AstUnpackArrayDType* const unpackDtp = VN_CAST(arrDtp->skipRefp(), UnpackArrayDType);
    if (!unpackDtp) return idxp;
    AstNodeExpr* const offsetp
        = new AstSub{fl, idxp, new AstConst{fl, static_cast<uint32_t>(unpackDtp->lo())}};
    offsetp->dtypeSetUInt32();
    return offsetp;
}

AstNodeExpr* RandomizeUtil::newIdxSelp(FileLine* const fl, AstNodeExpr* const arrp,
                                       AstVar* const idxVarp) {
    AstNodeDType* const arrDtp = arrp->dtypep()->skipRefp();
    // foreach gives the declared index, a select takes the offset
    AstNodeExpr* const offsetp
        = RandomizeUtil::newElemOffsetp(fl, arrDtp, new AstVarRef{fl, idxVarp, VAccess::READ});
    if (VN_IS(arrDtp, UnpackArrayDType)) return new AstArraySel{fl, arrp, offsetp};
    if (VN_IS(arrDtp, QueueDType)) return new AstQueueSel{fl, arrp, offsetp};
    if (VN_IS(arrDtp, AssocArrayDType)) return new AstAssocSel{fl, arrp, offsetp};
    if (VN_IS(arrDtp, WildcardArrayDType)) return new AstWildcardSel{fl, arrp, offsetp};
    return new AstDynArraySel{fl, arrp, offsetp};
}

AstNodeExpr* RandomizeUtil::newElemSelp(FileLine* const fl, AstNodeExpr* arrp,
                                        const std::vector<AstVar*>& idxVarps) {
    for (AstVar* const idxVarp : idxVarps) arrp = RandomizeUtil::newIdxSelp(fl, arrp, idxVarp);
    return arrp;
}

bool RandomizeUtil::isClassHandleArray(const AstVar* varp) {
    return varp->dtypep()->skipRefp()->isNonPackedArray()
           && VN_IS(RandomizeUtil::arrayElementDTypep(varp->dtypep()), ClassRefDType);
}

// The random index select into an array, random or not as randArray, that exprp reads through
static AstNodeExpr*
randIndexSelImpp(AstNodeExpr* exprp, bool randArray,
                 const std::function<bool(const AstNodeExpr* indexp)>& isRandIndexp) {
    // exprp is the select itself, or reached from it through member and element selects and
    // array methods, e.g. 'arr[idx].q.size()'. Each step is to the first operand, fromp.
    for (AstNodeExpr* curp = exprp;;) {
        AstNodeExpr* fromp;
        AstNodeExpr* indexp = nullptr;
        if (AstArraySel* const arraySelp = VN_CAST(curp, ArraySel)) {
            fromp = arraySelp->fromp();
            indexp = arraySelp->bitp();
        } else if (AstAssocSel* const assocSelp = VN_CAST(curp, AssocSel)) {
            fromp = assocSelp->fromp();
            indexp = assocSelp->bitp();
        } else if (AstDynArraySel* const selp = VN_CAST(curp, DynArraySel)) {
            fromp = selp->fromp();
            indexp = selp->bitp();
        } else if (AstQueueSel* const selp = VN_CAST(curp, QueueSel)) {
            fromp = selp->fromp();
            if (!selp->fromBack()) indexp = selp->bitp();
        } else if (AstCMethodHard* const methodp = VN_CAST(curp, CMethodHard)) {
            fromp = methodp->fromp();
        } else if (AstStructSel* const structSelp = VN_CAST(curp, StructSel)) {
            fromp = structSelp->fromp();
        } else if (AstMemberRef* const memberRefp = VN_CAST(curp, MemberRef)) {
            fromp = memberRefp->fromp();
        } else {
            return nullptr;
        }
        if (indexp && (fromp->user1() != 0) == randArray && isRandIndexp(indexp)) return curp;
        curp = fromp;
    }
}

AstNodeExpr* RandomizeUtil::randIndexSelp(AstNodeExpr* exprp,
                                          bool (*isRandIndexp)(const AstNodeExpr* indexp)) {
    return randIndexSelImpp(exprp, false, isRandIndexp);
}

AstNodeExpr* RandomizeUtil::randArrayIndexSelp(
    AstNodeExpr* exprp, const std::function<bool(const AstNodeExpr* indexp)>& isRandIndexp) {
    return randIndexSelImpp(exprp, true, isRandIndexp);
}

AstNodeExpr* RandomizeUtil::newElemModeOffp(AstNodeExpr* const modesp, AstNodeExpr* const indexp) {
    AstAssocSel* const selp
        = new AstAssocSel{indexp->fileline(), modesp, indexp->cloneTree(false)};
    selp->dtypeSetBit();
    return selp;
}

AstNodeExpr* RandomizeUtil::newMemberRefp(FileLine* const fl, AstNodeExpr* const objp,
                                          AstVar* const varp) {
    if (objp) return new AstMemberRef{fl, objp->cloneTreePure(false), varp};
    return new AstVarRef{fl, VN_AS(varp->user2p(), Class), varp, VAccess::READ};
}

AstClass* RandDispatch::randHandleClassp(const AstVar* varp) {
    if (!varp->rand().isRandomizable()) return nullptr;
    const AstClassRefDType* const classRefp = VN_CAST(varp->dtypep()->skipRefp(), ClassRefDType);
    return classRefp ? classRefp->classp() : nullptr;
}

bool RandDispatch::declaresDispatch(const AstClass* classp) {
    return classp->existsMember([&](const AstClass* declClassp, const AstNode* memberp) {
        const AstVar* const varp = VN_CAST(memberp, Var);
        return declClassp == classp
               && (VN_IS(memberp, Constraint) || (varp && randHandleClassp(varp)));
    });
}

void RandDispatch::addDispatchBases(const AstClass* classp,
                                    std::unordered_set<const AstClass*>& basesr) {
    const AstClassExtends* const extendsp = classp->extendsp();
    if (!extendsp) return;
    basesr.insert(extendsp->classp());
    addDispatchBases(extendsp->classp(), basesr);
}

void RandDispatch::addMerged(const AstClass* classp) {
    if (m_mergedps.insert(classp).second) m_pending.push_back(classp);
}

void RandDispatch::mergePending() {
    const AstClass* const classp = m_pending.back();
    m_pending.pop_back();
    for (const AstClass* const derivedp : m_derivedps[classp]) addMerged(derivedp);
    classp->existsMember([&](const AstClass*, const AstVar* varp) {
        if (const AstClass* const handleClassp = randHandleClassp(varp)) addMerged(handleClassp);
        return false;
    });
}

bool RandDispatch::isMergeable(const AstClass* classp) {
    // SMT symbols the constraints may use, which an SMT let binding of the name of a variable
    // of a merged object would hide (see VlRandomizer::merge_nested)
    static const std::unordered_set<std::string> s_smtSymbols{
        "_",      "and",         "bvadd",        "bvand",      "bvashr",
        "bvcomp", "bvlshr",      "bvmul",        "bvnand",     "bvneg",
        "bvnor",  "bvnot",       "bvor",         "bvsdiv",     "bvsge",
        "bvsgt",  "bvshl",       "bvsle",        "bvslt",      "bvsmod",
        "bvsrem", "bvsub",       "bvudiv",       "bvuge",      "bvugt",
        "bvule",  "bvult",       "bvurem",       "bvxnor",     "bvxor",
        "concat", "distinct",    "exists",       "extract",    "false",
        "forall", "ite",         "let",          "not",        "or",
        "repeat", "rotate_left", "rotate_right", "select",     "sign_extend",
        "store",  "true",        "xor",          "zero_extend"};
    // Nor array sizes, which the object's own randomize() solves first
    const bool sizes = classp->existsMember([](const AstClass*, const AstConstraint* constrp) {
        return constrp->exists([](const AstCMethodHard* methodp) {
            return methodp->method() == VCMethod::DYN_SIZE
                   || methodp->method() == VCMethod::ASSOC_SIZE;
        });
    });
    if (sizes) return false;
    // Nor arrays of class handles, whose objects' constraints are cloned into each class
    // randomizing them, not set up by the class holding the array
    return !classp->existsMember([](const AstClass*, const AstVar* varp) {
        if (!varp->rand().isRandomizable()) return false;
        const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
        const bool handleArray
            = dtypep->isNonPackedArray() && VN_IS(dtypep->subDTypep()->skipRefp(), ClassRefDType);
        return handleArray || s_smtSymbols.count(varp->name());
    });
}

std::unordered_set<const AstClass*>
RandDispatch::mergedClosure(const std::unordered_set<const AstClass*>& dispatchps) {
    m_mergedps.clear();
    for (const AstClass* const classp : dispatchps) addMerged(classp);
    while (!m_pending.empty()) mergePending();
    return std::move(m_mergedps);
}

RandDispatch::RandDispatch(AstNetlist* netlistp) {
    // A class whose objects may be of a derived class declaring constraints or rand class
    // handles needs the object's own constraints, so its handles dispatch
    std::unordered_set<const AstClass*> candidateps;
    netlistp->foreach([&](const AstClass* classp) {
        if (declaresDispatch(classp)) addDispatchBases(classp, candidateps);
        if (classp->extendsp()) m_derivedps[classp->extendsp()->classp()].push_back(classp);
    });
    // Merged: the dispatching classes, their derived classes, and the classes of their rand
    // class handles, and so on; unless one of those cannot be merged
    for (const AstClass* const classp : candidateps) {
        const std::unordered_set<const AstClass*> closureps = mergedClosure({classp});
        if (std::all_of(closureps.begin(), closureps.end(), isMergeable)) {
            m_dispatchps.insert(classp);
        }
    }
    m_mergedps = mergedClosure(m_dispatchps);
    m_derivedps.clear();
}

std::vector<std::vector<AstVar*>> RandDispatch::mergedPaths(AstClass* classp) const {
    std::vector<std::vector<AstVar*>> paths;
    if (m_mergedps.empty()) return paths;
    std::vector<AstVar*> path;
    std::unordered_set<const AstClass*> activeps{classp};
    const std::function<void(AstClass*)> walkp = [&](AstClass* holderp) {
        holderp->foreachMember([&](AstClass*, AstVar* varp) {
            AstClass* const handleClassp = randHandleClassp(varp);
            // Others are randomized by their own randomize(), so of their object's class
            if (!handleClassp || !varp->globalConstrained()) return;
            path.push_back(varp);
            if (mergesHandle(holderp, handleClassp)) {
                paths.push_back(path);
            } else if (activeps.insert(handleClassp).second) {
                walkp(handleClassp);
                activeps.erase(handleClassp);
            }
            path.pop_back();
        });
    };
    walkp(classp);
    return paths;
}
