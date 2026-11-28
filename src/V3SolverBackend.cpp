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
// V3SolverLowering

// Builds the methods of classes copying the random variables of the object, and those of the
// objects of its rand class handles by their methods, and assigning them back, or discarding the
// copies. As they are virtual, an object of a derived class copies its own variables too, and the
// code grows with the number of classes, not with the number of paths to the objects. A flag of
// the object, set by copying and cleared by assigning back or discarding, makes each object
// copied once, also if reached again through a cycle of handles. The copies of the variables a
// class declares are held by an object of a class of their own, made the first time they are
// copied and reused by later copies, so an object never copied takes no memory for them.
class RandomSaves final {
    VMemberMap& m_memberMap;  // Members of the classes
    V3UniqueNames& m_uniqueNames;  // Names of the copy objects
    const V3SolverLowering::DerivedClassMap& m_derived;  // Directly derived classes
    std::unordered_set<const AstClass*>& m_builtr;  // Classes with the methods
    // Handles of the objects holding the copies, by the class declaring the variables
    std::unordered_map<const AstClass*, AstVar*>& m_copyHandles;

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
    // The handle, member of declClassp, of the object holding the copies of the variables
    // declClassp declares
    AstVar* getCreateCopyHandlep(AstClass* declClassp) {
        AstVar*& handlep = m_copyHandles[declClassp];
        if (handlep) return handlep;
        FileLine* const fl = declClassp->fileline();
        const std::string name = m_uniqueNames.get("__VsavedRand");
        AstClass* const classp = new AstClass{fl, name + "_t", declClassp->libname()};
        AstFunc* const newp = new AstFunc{fl, "new"};
        newp->isConstructor(true);
        newp->classMethod(true);
        classp->addMembersp(newp);
        // Set while it holds the copies of an object, as a shallow copy of the object shares it
        AstVar* const busyp
            = new AstVar{fl, VVarType::MEMBER, BUSY_VAR_NAME, classp->findBitDType()};
        classp->addMembersp(busyp);
        m_memberMap.insert(classp, busyp);
        declClassp->addNextHere(classp);
        AstClassRefDType* const dtypep = new AstClassRefDType{fl, classp, nullptr};
        v3Global.rootp()->typeTablep()->addTypesp(dtypep);
        handlep = new AstVar{fl, VVarType::MEMBER, name, dtypep};
        declClassp->addMembersp(handlep);
        m_memberMap.insert(declClassp, handlep);
        return handlep;
    }
    static AstClass* copyClassp(const AstVar* handlep) {
        return VN_AS(handlep->dtypep(), ClassRefDType)->classp();
    }
    // The copy of varp, declared by declClassp, in the object holding the copies
    AstMemberRef* newCopyRefp(AstClass* declClassp, AstVar* varp, VAccess access) {
        FileLine* const fl = varp->fileline();
        AstVar* const handlep = getCreateCopyHandlep(declClassp);
        AstClass* const classp = copyClassp(handlep);
        AstVar* copyp = VN_CAST(m_memberMap.findMember(classp, varp->name()), Var);
        if (!copyp) {
            copyp = new AstVar{fl, VVarType::MEMBER, varp->name(), varp->dtypep()};
            classp->addMembersp(copyp);
            m_memberMap.insert(classp, copyp);
        }
        AstMemberRef* const refp
            = new AstMemberRef{fl, new AstVarRef{fl, declClassp, handlep, VAccess::READ}, copyp};
        refp->access(access);
        return refp;
    }
    // Make the object holding the copies of the variables declClassp declares, the first time
    // they are copied; later copies reuse it
    // Made unless one not holding the copies of another object exists
    AstNodeStmt* newCopyObjectStmtp(AstClass* declClassp, AstVar* handlep) {
        FileLine* const fl = declClassp->fileline();
        AstNodeExpr* const nullp
            = new AstEq{fl, new AstVarRef{fl, declClassp, handlep, VAccess::READ},
                        new AstConst{fl, AstConst::Null{}}};
        nullp->dtypeSetBit();
        AstNodeExpr* const condp
            = new AstLogOr{fl, nullp, newBusyRefp(declClassp, handlep, VAccess::READ)};
        condp->dtypeSetBit();
        AstNodeStmt* const stmtsp
            = new AstIf{fl, condp,
                        new AstAssign{fl, new AstVarRef{fl, declClassp, handlep, VAccess::WRITE},
                                      newCopyObjectp(handlep)}};
        stmtsp->addNext(newBusyAssignp(declClassp, handlep, true));
        return stmtsp;
    }
    AstMemberRef* newBusyRefp(AstClass* declClassp, AstVar* handlep, VAccess access) {
        FileLine* const fl = handlep->fileline();
        AstVar* const busyp
            = VN_AS(m_memberMap.findMember(copyClassp(handlep), BUSY_VAR_NAME), Var);
        AstMemberRef* const refp
            = new AstMemberRef{fl, new AstVarRef{fl, declClassp, handlep, VAccess::READ}, busyp};
        refp->access(access);
        return refp;
    }
    AstNodeStmt* newBusyAssignp(AstClass* declClassp, AstVar* handlep, bool busy) {
        FileLine* const fl = handlep->fileline();
        return new AstAssign{fl, newBusyRefp(declClassp, handlep, VAccess::WRITE),
                             new AstConst{fl, AstConst::BitTrue{}, busy}};
    }
    AstNew* newCopyObjectp(AstVar* handlep) {
        FileLine* const fl = handlep->fileline();
        AstClass* const classp = copyClassp(handlep);
        AstNew* const newp = new AstNew{fl};
        newp->taskp(VN_AS(m_memberMap.findMember(classp, "new"), NodeFTask));
        newp->dtypep(handlep->dtypep());
        newp->classOrPackagep(classp);
        return newp;
    }
    static bool hasCopiedVars(const AstClass* declClassp) {
        for (const AstNode* memberp = declClassp->membersp(); memberp;
             memberp = memberp->nextp()) {
            if (isCopiedVar(memberp)) return true;
        }
        return false;
    }
    // A member variable copied, rather than the object of a handle
    static bool isCopiedVar(const AstNode* memberp) {
        const AstVar* const varp = VN_CAST(memberp, Var);
        if (!varp || !varp->rand().isRandomizable()) return false;
        const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
        if (VN_IS(dtypep, ClassRefDType)) return false;
        const AstUnpackArrayDType* const arrDTypep = VN_CAST(dtypep, UnpackArrayDType);
        return !arrDTypep || !VN_IS(arrDTypep->subDTypep()->skipRefp(), ClassRefDType);
    }
    // The base-most class of classp, not an interface class it implements
    static AstClass* flagClassp(AstClass* classp) {
        while (classp->extendsp() && !classp->extendsp()->isImplements()) {
            classp = classp->extendsp()->classp();
        }
        return classp;
    }
    // The flag of the object, in the base-most class, so the same for every class of the object
    AstVar* getCreateFlagVarp(AstClass* classp) {
        AstClass* const basep = flagClassp(classp);
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
        AstClass* const basep = flagClassp(classp);
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
        // An interface class has no variables; the class of the object, implementing it,
        // overrides the methods
        if (!classp->isInterfaceClass()) {
            addClassVars(classp, savep, restorep, discardp);
            addFlagGuard(classp, savep, true);
            addFlagGuard(classp, restorep, false);
            addFlagGuard(classp, discardp, false);
        }
        // An object of a derived class copies its own variables by its override
        const auto it = m_derived.find(classp);
        if (it != m_derived.end()) buildList(it->second);
    }
    void buildList(const std::vector<AstClass*>& classps) {
        for (AstClass* const classp : classps) build(classp);
    }
    // Add the copies of the variables declClassp and its base classes declare
    void addClassVars(AstClass* declClassp, AstTask* savep, AstTask* restorep, AstTask* discardp) {
        AstVar* const handlep
            = hasCopiedVars(declClassp) ? getCreateCopyHandlep(declClassp) : nullptr;
        if (handlep) savep->addStmtsp(newCopyObjectStmtp(declClassp, handlep));
        for (AstNode* const memberp : declClassp->memberspList()) {
            addMember(declClassp, memberp, savep, restorep, discardp);
        }
        if (handlep) {
            restorep->addStmtsp(newBusyAssignp(declClassp, handlep, false));
            discardp->addStmtsp(newBusyAssignp(declClassp, handlep, false));
        }
        // The base class, not an interface class it implements
        const AstClassExtends* const extendsp = declClassp->extendsp();
        if (extendsp && !extendsp->isImplements()) {
            addClassVars(extendsp->classp(), savep, restorep, discardp);
        }
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
        } else if (!holdsClassHandles(dtypep) || isClearable(dtypep)) {
            // A static variable is copied by each object, so whichever objects are null
            savep->addStmtsp(new AstAssign{fl, newCopyRefp(declClassp, varp, VAccess::WRITE),
                                           new AstVarRef{fl, declClassp, varp, VAccess::READ}});
            restorep->addStmtsp(new AstAssign{fl,
                                              new AstVarRef{fl, declClassp, varp, VAccess::WRITE},
                                              newCopyRefp(declClassp, varp, VAccess::READ)});
            // A copy holding class handles is emptied when no longer needed, or it would keep
            // their objects alive, and through a cycle of handles back to the object, the object
            if (holdsClassHandles(dtypep)) {
                for (AstTask* const taskp : {restorep, discardp})
                    taskp->addStmtsp(
                        newClearp(newCopyRefp(declClassp, varp, VAccess::WRITE), dtypep));
            }
        }
        // Other values holding class handles, as structs, are not copied, nor restored
    }
    // Whether a value of dtypep holds class handles
    static bool holdsClassHandles(const AstNodeDType* dtypep) {
        dtypep = dtypep->skipRefp();
        if (VN_IS(dtypep, ClassRefDType)) return true;
        if (const AstNodeUOrStructDType* const sdtypep = VN_CAST(dtypep, NodeUOrStructDType)) {
            for (const AstMemberDType* itemp = sdtypep->membersp(); itemp;
                 itemp = VN_AS(itemp->nextp(), MemberDType))
                if (holdsClassHandles(itemp->subDTypep())) return true;
            return false;
        }
        return dtypep->isNonPackedArray() && holdsClassHandles(dtypep->subDTypep());
    }
    // Whether a value of dtypep is emptied by a method
    static bool isClearable(const AstNodeDType* dtypep) {
        return VN_IS(dtypep, DynArrayDType) || VN_IS(dtypep, QueueDType)
               || VN_IS(dtypep, AssocArrayDType) || VN_IS(dtypep, WildcardArrayDType);
    }
    // Empty the copy copyRefp of a value of dtypep
    static AstNodeStmt* newClearp(AstNodeExpr* copyRefp, const AstNodeDType* dtypep) {
        FileLine* const fl = copyRefp->fileline();
        const bool assoc = VN_IS(dtypep, AssocArrayDType) || VN_IS(dtypep, WildcardArrayDType);
        AstCMethodHard* const clearp = new AstCMethodHard{
            fl, copyRefp, assoc ? VCMethod::ASSOC_CLEAR : VCMethod::DYN_CLEAR};
        clearp->dtypeSetVoid();
        return clearp->makeStmt();
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
    static constexpr const char* BUSY_VAR_NAME = "__Vbusy";

    RandomSaves(VMemberMap& memberMap, V3UniqueNames& uniqueNames,
                const V3SolverLowering::DerivedClassMap& derived,
                std::unordered_set<const AstClass*>& builtr,
                std::unordered_map<const AstClass*, AstVar*>& copyHandles)
        : m_memberMap{memberMap}
        , m_uniqueNames{uniqueNames}
        , m_derived{derived}
        , m_builtr{builtr}
        , m_copyHandles{copyHandles} {}
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
        return new AstVarRef{classp->fileline(), flagClassp(classp), getCreateFlagVarp(classp),
                             access};
    }
};

AstNodeStmt* V3SolverLowering::addFailureRestore(AstFunc* funcp, AstClass* classp) {
    if (!m_derivedBuilt) {
        m_derivedBuilt = true;
        v3Global.rootp()->foreach([&](AstClass* derivedp) { addDerivedClass(derivedp); });
    }
    RandomSaves saves{m_memberMap, m_uniqueNames, m_derivedClassps, m_savedClasses,
                      m_savedCopyHandles};
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
    // Also the classes implementing an interface class
    for (const AstClassExtends* const extendsp : classp->extendspList()) {
        m_derivedClassps[extendsp->classp()].push_back(classp);
    }
}
