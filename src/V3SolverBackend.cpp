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

#include "V3MemberMap.h"
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
// RandomizeUtil implementation

AstNodeDType* RandomizeUtil::arrayElementDTypep(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefToEnump();
    while (dtypep->isNonPackedArray()) dtypep = dtypep->subDTypep()->skipRefToEnump();
    return dtypep;
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
    AstNodeDType* dtypep = varp->dtypep()->skipRefp();
    if (!dtypep->isNonPackedArray()) return false;
    while (dtypep->isNonPackedArray()) dtypep = dtypep->subDTypep()->skipRefp();
    return VN_IS(dtypep, ClassRefDType);
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
        if (indexp && !fromp->user1() && isRandIndexp(indexp)) return curp;
        curp = fromp;
    }
}

//######################################################################
// V3SolverLowering

// Builds the methods of classes copying the random variables of the object into variables of
// it, and those of the objects of its rand class handles by their methods, and assigning them
// back, or discarding the copies. As they are virtual, an object of a derived class copies its
// own variables too, and the code grows with the number of classes, not with the number of paths
// to the objects. A flag of the object, set by copying and cleared by assigning back or
// discarding, makes each object copied once, also if reached again through a cycle of handles.
class RandomSaves final {
    VMemberMap& m_memberMap;  // Members of the classes
    const V3SolverLowering::DerivedClassMap& m_derived;  // Directly derived classes
    std::unordered_set<const AstClass*>& m_builtr;  // Classes with the methods

    AstTask* getCreateTask(AstClass* classp, const char* name) {
        AstTask* taskp = VN_CAST(m_memberMap.findMember(classp, name), Task);
        if (taskp) return taskp;
        taskp = new AstTask{classp->fileline(), name};
        taskp->classMethod(true);
        taskp->isVirtual(classp->isExtended());
        // Rand class handles may hold objects of the same class, such as a tree of objects
        taskp->recursive(true);
        classp->addMembersp(taskp);
        m_memberMap.insert(classp, taskp);
        return taskp;
    }
    // The variable of the object holding the copy of varp, declared by declClassp
    AstVar* getCreateCopyVarp(AstClass* declClassp, AstVar* varp) {
        const std::string name = "__Vsaved_" + varp->name();
        AstVar* copyp = VN_CAST(m_memberMap.findMember(declClassp, name), Var);
        if (copyp) return copyp;
        copyp = new AstVar{varp->fileline(), VVarType::MEMBER, name, varp->dtypep()};
        declClassp->addMembersp(copyp);
        m_memberMap.insert(declClassp, copyp);
        return copyp;
    }
    // The flag of the object, in the base-most class, so the same for every class of the object
    AstVar* getCreateFlagVarp(AstClass* classp) {
        AstClass* const basep = classp->baseMostClassp();
        AstVar* flagp = VN_CAST(m_memberMap.findMember(basep, FLAG_VAR_NAME), Var);
        if (flagp) return flagp;
        flagp = new AstVar{basep->fileline(), VVarType::MEMBER, FLAG_VAR_NAME,
                           basep->findBitDType()};
        basep->addMembersp(flagp);
        m_memberMap.insert(basep, flagp);
        return flagp;
    }
    // Run the statements of taskp only if the flag is clear when copying, or set otherwise,
    // and set or clear it
    void addFlagGuard(AstClass* classp, AstTask* taskp, bool saving) {
        FileLine* const fl = taskp->fileline();
        AstVar* const flagp = getCreateFlagVarp(classp);
        AstClass* const basep = classp->baseMostClassp();
        AstNodeStmt* const stmtsp
            = taskp->stmtsp() ? taskp->stmtsp()->unlinkFrBackWithNext() : nullptr;
        AstNodeExpr* condp = new AstVarRef{fl, basep, flagp, VAccess::READ};
        if (saving) condp = new AstLogNot{fl, condp};
        AstNodeStmt* const setp
            = new AstAssign{fl, new AstVarRef{fl, basep, flagp, VAccess::WRITE},
                            new AstConst{fl, AstConst::BitTrue{}, saving}};
        taskp->addStmtsp(new AstIf{fl, condp, AstNode::addNextNull(setp, stmtsp)});
    }
    void buildMethods(AstClass* classp) {
        AstTask* const savep = getCreateTask(classp, SAVE_FUNC_NAME);
        AstTask* const restorep = getCreateTask(classp, RESTORE_FUNC_NAME);
        AstTask* const discardp = getCreateTask(classp, DISCARD_FUNC_NAME);
        addClassVars(classp, savep, restorep, discardp);
        addFlagGuard(classp, savep, true);
        addFlagGuard(classp, restorep, false);
        addFlagGuard(classp, discardp, false);
        // An object of a derived class copies its own variables by its override
        const auto it = m_derived.find(classp);
        if (it != m_derived.end()) buildList(it->second);
    }
    void buildList(const std::vector<AstClass*>& classps) {
        for (AstClass* const classp : classps) build(classp);
    }
    // Add the copies of the variables declClassp and its base classes declare
    void addClassVars(AstClass* declClassp, AstTask* savep, AstTask* restorep, AstTask* discardp) {
        for (AstNode* const memberp : declClassp->memberspList()) {
            addMember(declClassp, memberp, savep, restorep, discardp);
        }
        AstClassExtends* const extendsp = declClassp->extendsp();
        if (extendsp) addClassVars(extendsp->classp(), savep, restorep, discardp);
    }
    void addMember(AstClass* declClassp, AstNode* memberp, AstTask* savep, AstTask* restorep,
                   AstTask* discardp) {
        AstVar* const varp = VN_CAST(memberp, Var);
        if (varp && varp->rand().isRandomizable()) {
            addVar(declClassp, varp, savep, restorep, discardp);
        }
    }
    void addVar(AstClass* declClassp, AstVar* varp, AstTask* savep, AstTask* restorep,
                AstTask* discardp) {
        FileLine* const fl = varp->fileline();
        const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
        const AstUnpackArrayDType* const arrDTypep = VN_CAST(dtypep, UnpackArrayDType);
        const AstClassRefDType* const objDTypep = VN_CAST(dtypep, ClassRefDType);
        const AstClassRefDType* const elemDTypep
            = arrDTypep ? VN_CAST(arrDTypep->subDTypep()->skipRefp(), ClassRefDType) : nullptr;
        if (objDTypep) {
            // The objects of rand handles are kept too; randomize() does not change the
            // handles themselves
            addObject(new AstVarRef{fl, declClassp, varp, VAccess::READ}, objDTypep->classp(),
                      savep, restorep, discardp);
        } else if (elemDTypep) {
            // Of a fixed-size array of handles, each element's; those of a dynamic array or
            // queue of handles are not kept
            addElements(declClassp, varp, arrDTypep->elementsConst(), elemDTypep->classp(), savep,
                        restorep, discardp);
        } else {
            // A static variable is copied by each object, so whichever objects are null
            AstVar* const copyp = getCreateCopyVarp(declClassp, varp);
            savep->addStmtsp(new AstAssign{fl,
                                           new AstVarRef{fl, declClassp, copyp, VAccess::WRITE},
                                           new AstVarRef{fl, declClassp, varp, VAccess::READ}});
            restorep->addStmtsp(
                new AstAssign{fl, new AstVarRef{fl, declClassp, varp, VAccess::WRITE},
                              new AstVarRef{fl, declClassp, copyp, VAccess::READ}});
        }
    }
    void addElements(AstClass* declClassp, AstVar* varp, int elements, AstClass* elemClassp,
                     AstTask* savep, AstTask* restorep, AstTask* discardp) {
        for (int i = 0; i < elements; ++i) {
            addElement(declClassp, varp, i, elemClassp, savep, restorep, discardp);
        }
    }
    void addElement(AstClass* declClassp, AstVar* varp, int i, AstClass* elemClassp,
                    AstTask* savep, AstTask* restorep, AstTask* discardp) {
        FileLine* const fl = varp->fileline();
        addObject(new AstArraySel{fl, new AstVarRef{fl, declClassp, varp, VAccess::READ}, i},
                  elemClassp, savep, restorep, discardp);
    }
    // Call the methods of the object objp, of objClassp or a derived class, if not null, and
    // delete objp
    void addObject(AstNodeExpr* objp, AstClass* objClassp, AstTask* savep, AstTask* restorep,
                   AstTask* discardp) {
        build(objClassp);
        savep->addStmtsp(newObjectCallp(objp, objClassp, SAVE_FUNC_NAME));
        restorep->addStmtsp(newObjectCallp(objp, objClassp, RESTORE_FUNC_NAME));
        discardp->addStmtsp(newObjectCallp(objp, objClassp, DISCARD_FUNC_NAME));
        VL_DO_DANGLING(objp->deleteTree(), objp);
    }
    AstNodeStmt* newObjectCallp(AstNodeExpr* objp, AstClass* objClassp, const char* name) {
        FileLine* const fl = objp->fileline();
        AstTask* const taskp = getCreateTask(objClassp, name);
        AstMethodCall* const callp = new AstMethodCall{fl, objp->cloneTree(false), name};
        callp->taskp(taskp);
        callp->dtypeSetVoid();
        return new AstIf{
            fl, new AstNeq{fl, objp->cloneTree(false), new AstConst{fl, AstConst::Null{}}},
            callp->makeStmt()};
    }

public:
    static constexpr const char* SAVE_FUNC_NAME = "__VsaveRand";
    static constexpr const char* RESTORE_FUNC_NAME = "__VrestoreRand";
    static constexpr const char* DISCARD_FUNC_NAME = "__VdiscardRand";
    static constexpr const char* FLAG_VAR_NAME = "__VsavedRand";

    RandomSaves(VMemberMap& memberMap, const V3SolverLowering::DerivedClassMap& derived,
                std::unordered_set<const AstClass*>& builtr)
        : m_memberMap{memberMap}
        , m_derived{derived}
        , m_builtr{builtr} {}
    // Build the methods of classp, once
    void build(AstClass* classp) {
        if (m_builtr.emplace(classp).second) buildMethods(classp);
    }
    // Call of the method name of this object, of classp or a derived class
    AstNodeStmt* newThisCallp(AstClass* classp, const char* name) {
        return (new AstTaskRef{classp->fileline(), getCreateTask(classp, name)})->makeStmt();
    }
    // Reference to the flag of this object, of classp or a derived class
    AstVarRef* newThisFlagRefp(AstClass* classp, VAccess access) {
        return new AstVarRef{classp->fileline(), classp->baseMostClassp(),
                             getCreateFlagVarp(classp), access};
    }
};

AstNodeStmt* V3SolverLowering::addFailureRestore(AstFunc* funcp, AstClass* classp) {
    if (!m_derivedBuilt) {
        m_derivedBuilt = true;
        v3Global.rootp()->foreach([&](AstClass* derivedp) { addDerivedClass(derivedp); });
    }
    RandomSaves saves{m_memberMap, m_derivedClassps, m_savedClasses};
    saves.build(classp);
    // A randomize() of an object already copied by the call randomizing another one, as its
    // member, leaves its copies to that call
    FileLine* const fl = funcp->fileline();
    AstVar* const ownerp = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__VsavedHere"),
                                      classp->findBitDType()};
    ownerp->funcLocal(true);
    ownerp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
    funcp->addDeclsp(ownerp);
    funcp->addStmtsp(
        new AstAssign{fl, new AstVarRef{fl, ownerp, VAccess::WRITE},
                      new AstLogNot{fl, saves.newThisFlagRefp(classp, VAccess::READ)}});
    funcp->addStmtsp(saves.newThisCallp(classp, RandomSaves::SAVE_FUNC_NAME));
    return new AstIf{fl, new AstVarRef{fl, ownerp, VAccess::READ},
                     new AstIf{fl, new AstVarRef{fl, funcp->fvarp(), VAccess::READ},
                               saves.newThisCallp(classp, RandomSaves::DISCARD_FUNC_NAME),
                               saves.newThisCallp(classp, RandomSaves::RESTORE_FUNC_NAME)}};
}
void V3SolverLowering::addDerivedClass(AstClass* classp) {
    if (AstClassExtends* const extendsp = classp->extendsp()) {
        m_derivedClassps[extendsp->classp()].push_back(classp);
    }
}
