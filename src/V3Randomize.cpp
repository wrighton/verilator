// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Generate randomization procedures
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
// V3Randomize's Transformations:
//
// Each randomize() method call:
//      Mark class of object on which randomize() is called
// Mark all classes that inherit from previously marked classed
// Mark all classes whose instances are randomized member variables of marked classes
// Each marked class:
//      * define a virtual randomize() method that randomizes its random variables
// Each call to randomize():
//      * define __Vrandwith### functions for randomize() calls with inline constraints and
//        put then into randomized classes
//      * replace calls to randomize() that use inline constraints with calls to __Vrandwith###
//        functions
// The constraints of each randomize() are lowered by the constraint solver
// back-end (V3SolverBackend.h); this file is the solver-neutral front end.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "verilatedos.h"

#include "V3Randomize.h"

#include "V3Ast.h"
#include "V3ConstPool.h"
#include "V3Error.h"
#include "V3FileLine.h"
#include "V3Global.h"
#include "V3LinkLValue.h"
#include "V3MemberMap.h"
#include "V3SolverBackend.h"
#include "V3UniqueNames.h"

#include <queue>
#include <tuple>
#include <utility>

VL_DEFINE_DEBUG_FUNCTIONS;

// ######################################################################
// Determines if a class is used with randomization

enum ClassRandom : uint8_t {
    NONE,  // randomize() is not called
    IS_RANDOMIZED,  // randomize() is called
    IS_RANDOMIZED_GLOBAL,  // randomize() is called with global constraints
    IS_RANDOMIZED_INLINE,  // randomize() with args is called
    IS_STD_RANDOMIZED,  // std::randomize() is called
};

// ######################################################################
// Establishes the target of a rand_mode() call

// Check if two expressions select the same data, however their variables are referenced
static bool sameSelection(const AstNode* ap, const AstNode* bp, bool withNext = false) {
    // Not sameTree(): a std::randomize() argument is a read-write reference, and a 'with'
    // clause reference is a read, with the class of a static variable
    do {
        if (!ap || !bp) return ap == bp;
        if (ap->type() != bp->type()) return false;
        if (const AstNodeVarRef* const refp = VN_CAST(ap, NodeVarRef)) {
            if (refp->varp() != VN_AS(bp, NodeVarRef)->varp()) return false;
        } else if (const AstMemberSel* const selp = VN_CAST(ap, MemberSel)) {
            const AstMemberSel* const bselp = VN_AS(bp, MemberSel);
            if (selp->varp() != bselp->varp() || !sameSelection(selp->fromp(), bselp->fromp())) {
                return false;
            }
        } else if (!ap->isSame(bp) || !sameSelection(ap->op1p(), bp->op1p(), true)
                   || !sameSelection(ap->op2p(), bp->op2p(), true)
                   || !sameSelection(ap->op3p(), bp->op3p(), true)
                   || !sameSelection(ap->op4p(), bp->op4p(), true)) {
            return false;
        }
        ap = ap->nextp();
        bp = bp->nextp();
    } while (withNext);
    return true;
}

// Array of the one-dimensional integral or handle element selected by fromp, else nullptr
static AstVar* randModeElemArrayp(AstNodeExpr* fromp) {
    AstNodeExpr* arrayp = nullptr;
    if (const AstArraySel* const arraySelp = VN_CAST(fromp, ArraySel)) {
        arrayp = arraySelp->fromp();
    } else if (const AstCMethodHard* const atp = VN_CAST(fromp, CMethodHard)) {
        if (atp->method() == VCMethod::ARRAY_AT) arrayp = atp->fromp();
    }
    AstVar* varp = nullptr;
    if (const AstVarRef* const varrefp = VN_CAST(arrayp, VarRef)) {
        varp = varrefp->varp();
    } else if (const AstMemberSel* const memberSelp = VN_CAST(arrayp, MemberSel)) {
        varp = memberSelp->varp();
    }
    // One dimension of an array of integral or class handle elements
    if (!varp) return nullptr;
    const AstNodeDType* const elemDtp = fromp->dtypep()->skipRefp();
    if (!elemDtp->isIntegralOrPacked() && !VN_IS(elemDtp, ClassRefDType)) return nullptr;
    return varp;
}

// Whether a packed type holds an enum, possibly inside packed arrays, structs or unions
static bool packedHasEnum(const AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefToEnump();
    if (VN_IS(dtypep, EnumDType)) return true;
    if (const AstPackArrayDType* const arrayDtp = VN_CAST(dtypep, PackArrayDType)) {
        return packedHasEnum(arrayDtp->subDTypep());
    }
    if (const AstNodeUOrStructDType* const structDtp = VN_CAST(dtypep, NodeUOrStructDType)) {
        for (const AstMemberDType* const memberp : structDtp->memberspList()) {
            if (packedHasEnum(memberp->subDTypep())) return true;
        }
    }
    return false;
}

struct RandModeTarget final {
    // MEMBERS
    AstVar* const receiverp;  // Variable that is the target of the rand_mode() call
    AstNodeExpr* const fromp;  // Expression from which the rand_mode() call originates
    AstClass* const classp;  // Class in which rand_mode should be set

    // METHODS
    static RandModeTarget get(AstNodeExpr* fromp, AstNodeModule* modp) {
        if (!fromp) return {nullptr, nullptr, VN_AS(modp, Class)};
        if (AstCMethodHard* const methodHardp = VN_CAST(fromp, CMethodHard)) {
            return RandModeTarget::get(methodHardp->fromp(), modp);
        }
        if (AstArraySel* const arraySelp = VN_CAST(fromp, ArraySel)) {
            return RandModeTarget::get(arraySelp->fromp(), modp);
        }
        AstVar* receiverp = nullptr;
        AstClass* classp = VN_CAST(modp, Class);
        if (AstVarRef* const varrefp = VN_CAST(fromp, VarRef)) {
            receiverp = varrefp->varp();
            if (receiverp->isRand()) {
                fromp = nullptr;
                if (receiverp->lifetime().isStatic()) {
                    classp = VN_AS(varrefp->classOrPackagep(), Class);
                }
            }
        } else if (AstMemberSel* const memberSelp = VN_CAST(fromp, MemberSel)) {
            receiverp = memberSelp->varp();
            if (receiverp->isRand()) {
                fromp = memberSelp->fromp();
                classp = VN_AS(fromp->dtypep()->skipRefp(), ClassRefDType)->classp();
            }
        }
        UASSERT_OBJ(receiverp, fromp, "Unknown rand_mode() receiver");
        if (!receiverp->isRand()) {
            AstClassRefDType* const classRefDtp
                = VN_CAST(receiverp->dtypep()->skipRefp(), ClassRefDType);
            if (classRefDtp) classp = classRefDtp->classp();
        }
        return {receiverp, fromp, classp};
    }
};

// Check a rand/randc variable's type against IEEE 1800-2023 18.4's
// allowed list. Purely diagnostic: codegen sites that would otherwise
// mishandle one of these types guard themselves on V3Error::errorCount()
// rather than relying on anything checked here.
static void checkRandTypeEligibility(AstNode* contextp, AstNodeDType* dtypep, bool isRandc) {
    dtypep = dtypep->skipRefp();
    if (AstNodeDType* const subp = dtypep->subDTypep()) {
        checkRandTypeEligibility(contextp, subp, isRandc);  // Containers inherit rand/randc kind
        return;
    }
    if (VN_IS(dtypep, ClassRefDType)) {
        // rand on a class handle is legal (recursive randomization).
        // Only randc is disallowed.
        if (isRandc) {
            contextp->v3error("'randc' on an object handle (IEEE 1800-2023 18.4: object "
                              "handles shall not be declared randc)");
        }
        return;
    }
    if (const AstIfaceRefDType* const ifacep = VN_CAST(dtypep, IfaceRefDType)) {
        // A class property can only hold a *virtual* interface handle --
        // a plain interface can't be a class member at all -- so a
        // rand-qualified var landing here is always the virtual kind.
        UASSERT_OBJ(ifacep->isVirtual(), dtypep, "Non-virtual interface as class property type");
        // Not in 18.4's enumerated random-variable domain, same reasoning
        // as chandle/string/event; also generates C++ that does not
        // compile if left unchecked.
        contextp->v3error("'rand'/'randc' on a virtual interface handle (not "
                          "in IEEE 1800-2023 18.4's random-variable type domain)");
        return;
    }
    if (const AstNodeUOrStructDType* const structp = VN_CAST(dtypep, NodeUOrStructDType)) {
        if (structp->packed()) return;  // Integral by construction; members checked separately
        if (VN_IS(structp, UnionDType)) {
            contextp->v3error("'rand'/'randc' on an unpacked union (IEEE "
                              "1800-2023 18.4: unpacked unions shall not be declared as rand "
                              "or randc)");
            return;
        }
        for (AstMemberDType* const memberp : structp->memberspList()) {
            // Each unpacked-struct member independently declares its own rand/randc.
            if (memberp->rand().isRandomizable()) {
                checkRandTypeEligibility(memberp, memberp->subDTypep(), memberp->rand().isRandC());
            }
        }
        return;
    }
    const AstBasicDType* const basicp = VN_CAST(dtypep, BasicDType);
    // V3Width has already resolved every dtype by this pass, and every
    // other leaf kind (class handle, virtual interface, struct/union) was
    // already dispatched above, so a rand-qualified var's dtype can only
    // be a BasicDType here.
    UASSERT_OBJ(basicp, dtypep, "Unexpected non-basic leaf dtype for rand var");
    if (basicp->isDouble()) {
        // rand on a real variable is legal; only randc is disallowed.
        if (isRandc) {
            contextp->v3error("'randc' on a real variable (IEEE 1800-2023 18.4: "
                              "real variables shall not be declared randc)");
        }
        return;
    }
    switch (basicp->keyword()) {
    case VBasicDTypeKwd::STRING:
    case VBasicDTypeKwd::CHANDLE:
    case VBasicDTypeKwd::EVENT: {
        const char* const articlep = basicp->keyword() == VBasicDTypeKwd::EVENT ? "an" : "a";
        contextp->v3error("'rand'/'randc' on " << articlep << " " << basicp->keyword().typeName()
                                               << " variable (not in IEEE 1800-2023 18.4's "
                                                  "random-variable type domain)");
        break;
    }
    default: break;
    }
}

//######################################################################
// Visitor that marks classes needing a randomize() method

class RandomizeMarkVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared on Netlist
    //  AstClass::user1()       -> bool.  Set true to indicate needs randomize processing
    //  AstNodeModule::user1()  -> bool.  Set true to indicate needs std::randomize processing
    //  AstNodeExpr::user1()    -> bool.  Set true to indicate constraint expression depending on a
    //                                    randomized variable
    //  AstVar::user1()         -> bool.  Set true to indicate needs rand_mode
    //  AstVar::user2p()        -> AstNodeModule*. Pointer to containing module
    //  AstNodeFTask::user2p()  -> AstNodeModule*. Pointer to containing module
    //  AstMemberSel::user2p()  -> AstNodeModule*. Pointer to containing module, nullptr if
    //                                    in a cloned constraint
    const VNUser1InUse m_inuser1;
    const VNUser2InUse m_inuser2;

    using BaseToDerivedMap = std::unordered_map<const AstClass*, std::vector<AstClass*>>;

    BaseToDerivedMap m_baseToDerivedMap;  // Mapping from base classes to classes that extend them
    std::vector<AstClass*> m_classps;  // All classes, in tree order
    AstClass* m_classp = nullptr;  // Current class
    AstNode* m_constraintExprGenp = nullptr;  // Current constraint or constraint if expression
    AstNodeModule* m_modp = nullptr;  // Current module
    AstNodeStmt* m_stmtp = nullptr;  // Current statement
    AstNodeFTaskRef* m_stdRandCallp = nullptr;  // Current std::randomize() call
    bool m_inStdWith = false;  // True when inside a 'with {}' clause
    std::set<AstNodeVarRef*> m_staticRefs;  // References to static variables under `with` clauses
    AstWith* m_withp = nullptr;  // Current 'with' constraint node
    ClonedConstraints& m_cloneObjps;  // Constraints made by cloning
    std::unordered_set<AstVar*>& m_elemModeArrays;  // Arrays with per-element rand_mode()
    AstClass* m_withClassp = nullptr;  // Class of obj in the current obj.randomize() with

    // METHODS
    // Mark the rand variables, except handles, of the class of a globally constrained member
    void markGlobalConstrainedVars(const AstClass* classp) {
        for (const AstClass* cp = classp; cp;
             cp = cp->extendsp() ? cp->extendsp()->classp() : nullptr) {
            for (AstNode* const memberp : cp->memberspList()) {
                AstVar* const varp = VN_CAST(memberp, Var);
                if (!varp || !varp->rand().isRandomizable()) continue;
                // A handle is globally constrained only if a constraint selects through it
                if (!VN_IS(varp->dtypep()->skipRefp(), ClassRefDType))
                    varp->globalConstrained(true);
            }
        }
    }
    // Whether an array index depends on a variable being randomized, by its marks
    static bool isMarkedRandIndex(const AstNodeExpr* indexp) {
        // Not isRandIndex: std::randomize() arguments get their own variables only later
        return indexp->exists([](const AstNode* const nodep) {
            return (VN_IS(nodep, NodeVarRef) || VN_IS(nodep, MemberSel)) && nodep->user1();
        });
    }
    // Whether a constraint of the class has two member selects not from a variable or member
    static bool selectsElementMembersTwice(const AstClass* classp) {
        // Such as selects of object array elements, which a constraint cloned for an object of
        // the class may not support ("Multiple expressions inside indices"), so such an object
        // keeps its own randomize()
        return classp->existsMember([](const AstClass*, const AstConstraint* constrp) {
            int count = 0;
            constrp->foreach([&](const AstMemberSel* selp) {
                if (!VN_IS(selp->fromp(), NodeVarRef) && !VN_IS(selp->fromp(), MemberSel)) ++count;
            });
            return count > 1;
        });
    }
    // Mark the rand handles that the member selects of a constraint select through
    static void markSelectedHandles(AstNode* nodep) {
        // Such a member is solved with the class of the constraint, so the constraint and the
        // member's own constraints are solved together (IEEE 1800-2023 18.5.8). Other members
        // are randomized by their own randomize().
        nodep->foreach([](const AstMemberSel* selp) {
            AstVar* varp = nullptr;
            if (const AstNodeVarRef* const refp = VN_CAST(selp->fromp(), NodeVarRef)) {
                varp = refp->varp();
            } else if (const AstMemberSel* const fromSelp = VN_CAST(selp->fromp(), MemberSel)) {
                varp = fromSelp->varp();
            }
            if (varp && varp->rand().isRandomizable()) varp->globalConstrained(true);
        });
    }
    // Check if an expression in a 'with' clause is a std::randomize() argument
    bool isStdRandomizeArg(const AstNodeExpr* exprp) const {
        if (!m_inStdWith || !m_stdRandCallp) return false;
        // Only the arguments are random (IEEE 1800-2023 18.12); for arr[0], not arr[1]
        for (AstArg* const argp : m_stdRandCallp->argspList()) {
            if (sameSelection(exprp, argp->exprp())) return true;
        }
        return false;
    }
    void markMembers(const AstClass* nodep) {
        for (const AstClass* classp = nodep; classp;
             classp = classp->extendsp() ? classp->extendsp()->classp() : nullptr) {
            for (AstNode* const memberp : classp->memberspList()) {
                AstVar* const varp = VN_CAST(memberp, Var);
                if (!varp) continue;
                // If member is randomizable and of class type, mark its class
                if (varp->rand().isRandomizable()) {
                    // Also the elements of arrays of any dimension
                    const AstClassRefDType* const classRefp = VN_CAST(
                        RandomizeUtil::arrayElementDTypep(varp->dtypep()), ClassRefDType);
                    if (classRefp) {
                        AstClass* const rclassp = classRefp->classp();
                        if (!rclassp->user1()) {
                            rclassp->user1(IS_RANDOMIZED_GLOBAL);
                            markMembers(rclassp);
                            markDerived(rclassp);
                        }
                    }
                    // If the class is randomized inline, all members use rand mode
                    if (nodep->user1() == IS_RANDOMIZED_INLINE) {
                        RandomizeMode randMode = {};
                        randMode.usesMode = true;
                        varp->user1(randMode.asUQuad);
                    }
                }
            }
        }
    }
    void markDerived(const AstClass* nodep) {
        const auto it = m_baseToDerivedMap.find(nodep);
        if (it != m_baseToDerivedMap.end()) {
            for (AstClass* const classp : it->second) {
                if (classp->user1() < nodep->user1()) {
                    classp->user1(nodep->user1());
                    markMembers(classp);
                    markDerived(classp);
                }
            }
        }
    }
    void markAllDerived() {
        // In tree order, so the marking does not depend on the memory layout
        for (const AstClass* const classp : m_classps) {
            if (classp->user1()) markDerived(classp);
        }
    }
    // Mark the globally constrained members, and clone the constraints of their objects
    void cloneMemberConstraints() {
        // __VBasicRand does not randomize the solver variables of such an object, so every
        // class having the member solves them. They are cloned into the declaring class of the
        // member, which all such classes inherit. As the marks depend only on the constraints,
        // they do not depend on the order of the classes or randomize() calls.
        for (AstClass* const classp : m_classps) {
            for (AstNode* const memberp : classp->memberspList()) {
                if (VN_IS(memberp, Constraint)) markSelectedHandles(memberp);
            }
        }
        std::vector<std::pair<AstClass*, AstVar*>> handles;  // Owner class and handle
        for (AstClass* const classp : m_classps) {
            for (AstNode* const memberp : classp->memberspList()) {
                AstVar* const varp = VN_CAST(memberp, Var);
                if (!varp || !varp->globalConstrained()) continue;
                const AstClassRefDType* const classRefp
                    = VN_CAST(varp->dtypep()->skipRefp(), ClassRefDType);
                if (!classRefp) continue;
                if (selectsElementMembersTwice(classRefp->classp())) {
                    varp->globalConstrained(false);
                    continue;
                }
                markGlobalConstrainedVars(classRefp->classp());
                handles.emplace_back(classp, varp);
            }
        }
        for (const std::pair<AstClass*, AstVar*>& classVar : handles) {
            AstClass* const classp = classVar.first;
            AstVar* const varp = classVar.second;
            AstClass* const memberClassp
                = VN_AS(varp->dtypep()->skipRefp(), ClassRefDType)->classp();
            AstVarRef* const rootVarRefp
                = new AstVarRef{varp->fileline(), classp, varp, VAccess::READ};
            const std::vector<AstVar*> emptyPath;
            memberClassp->foreachMember([&](AstClass* const, AstConstraint* const constrp) {
                processNestedConstraint(constrp, rootVarRefp, emptyPath, classp);
            });
            cloneNestedConstraintsRecurse(rootVarRefp, memberClassp, emptyPath, classp);
            VL_DO_DANGLING(rootVarRefp->deleteTree(), rootVarRefp);
        }
        // Into each randomized class, as only the class's constraints decide whether needed
        for (AstClass* const classp : m_classps) {
            if (!classp->user1()) continue;
            classp->foreachMember([&](AstClass* const ownerClassp, AstVar* const memberVarp) {
                if (!memberVarp->rand().isRandomizable() || !isHandleArray(memberVarp)) return;
                AstVarRef* const arrRefp = new AstVarRef{memberVarp->fileline(), ownerClassp,
                                                         memberVarp, VAccess::READ};
                cloneElementConstraints(arrRefp, memberVarp->name(), classp);
                VL_DO_DANGLING(arrRefp->deleteTree(), arrRefp);
            });
        }
    }
    void setPackageRefs() {
        for (AstNodeVarRef* staticRefp : m_staticRefs) {
            UINFO(9, "Updated classOrPackage ref for " << staticRefp->name());
            staticRefp->classOrPackagep(VN_AS(staticRefp->varp()->user2p(), NodeModule));
        }
    }
    void markNestedGlobalConstrainedRecurse(AstNode* nodep) {
        if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
            AstVar* const varp = refp->varp();
            if (varp->globalConstrained()) return;
            varp->globalConstrained(true);
        } else if (const AstMemberSel* const memberSelp = VN_CAST(nodep, MemberSel)) {
            if (memberSelp->varp()) {
                AstVar* const varp = memberSelp->varp();
                if (varp->globalConstrained()) return;
                varp->globalConstrained(true);
            }
            markNestedGlobalConstrainedRecurse(memberSelp->fromp());
        }
    }

    // Build MemberSel chain from variable path
    AstNodeExpr* buildMemberSelChain(AstVarRef* rootVarRefp, const std::vector<AstVar*>& path) {
        AstNodeExpr* exprp = rootVarRefp->cloneTree(false);
        for (AstVar* memberVarp : path) {
            AstMemberSel* memberSelp
                = new AstMemberSel{rootVarRefp->fileline(), exprp, memberVarp};
            memberSelp->user2p(m_classp);
            exprp = memberSelp;
        }
        return exprp;
    }

    // Clone constraint constrp of the object objp, nullptr if targetClassp already has the clone
    AstConstraint* cloneObjectConstraint(AstConstraint* const constrp, AstNodeExpr* objp,
                                         const std::string& pathPrefix, AstClass* targetClassp) {
        const std::string newName = pathPrefix + GLOBAL_CONSTRAINT_SEPARATOR + constrp->name();

        // Check if this constraint already exists in the target class
        bool isDuplicate = false;
        targetClassp->foreachMember([&](AstClass* const, AstConstraint* const existingConstrp) {
            if (existingConstrp->name() == newName) {
                // Multiple paths lead to same constraint - unsupported pattern
                isDuplicate = true;
            }
        });
        if (isDuplicate) return nullptr;

        AstConstraint* const cloneConstrp = constrp->cloneTree(false);
        cloneConstrp->name(newName);

        // FuncRefs are converted after the traversal. Converting moves the args under the new
        // MethodCall, where foreach would not visit VarRefs or nested calls such as add(lim()).
        std::vector<AstFuncRef*> funcRefps;
        cloneConstrp->foreach([&](AstNodeExpr* exprp) {
            if (AstVarRef* const varRefp = VN_CAST(exprp, VarRef)) {
                if (!varRefp->varp()->isClassMember()) return;
                AstMemberSel* const finalSelp = new AstMemberSel{
                    varRefp->fileline(), objp->cloneTree(false), varRefp->varp()};
                finalSelp->user2p(m_classp);
                varRefp->replaceWith(finalSelp);
                VL_DO_DANGLING(pushDeletep(varRefp), varRefp);
            } else if (AstFuncRef* const funcRefp = VN_CAST(exprp, FuncRef)) {
                // Static and non-member calls are correctly qualified already
                if (funcRefp->taskp()->classMethod() && !funcRefp->taskp()->isStatic()) {
                    funcRefps.push_back(funcRefp);
                }
            }
        });
        for (AstFuncRef* funcRefp : funcRefps) {
            AstArg* const argsp
                = funcRefp->argsp() ? funcRefp->argsp()->unlinkFrBackWithNext() : nullptr;
            AstMethodCall* const callp = new AstMethodCall{
                funcRefp->fileline(), objp->cloneTree(false), funcRefp->name(), argsp};
            callp->taskp(funcRefp->taskp());
            callp->classOrPackagep(funcRefp->classOrPackagep());
            callp->dtypep(funcRefp->dtypep());
            callp->superReference(funcRefp->superReference());
            funcRefp->replaceWith(callp);
            VL_DO_DANGLING(pushDeletep(funcRefp), funcRefp);
        }
        return cloneConstrp;
    }
    // Add a constraint cloned from origp for the object (or object array) objp to targetClassp
    void addClonedConstraint(AstClass* targetClassp, AstConstraint* cloneConstrp,
                             AstConstraint* origp, AstNodeExpr* objp) {
        m_cloneObjps.emplace(cloneConstrp, ClonedConstraint{objp->cloneTree(false), origp});
        targetClassp->addMembersp(cloneConstrp);
        // Immediately iterate to set user1 marks
        iterateConst(cloneConstrp);
    }

    // Name prefix of the constraints cloned from the object at path
    static std::string clonePathPrefix(const AstVarRef* rootVarRefp,
                                       const std::vector<AstVar*>& path) {
        std::string pathPrefix = rootVarRefp->name();
        for (const AstVar* const pathMemberVarp : path) {
            pathPrefix += GLOBAL_CONSTRAINT_SEPARATOR + pathMemberVarp->name();
        }
        return pathPrefix;
    }

    // Process a single constraint during nested constraint cloning
    void processNestedConstraint(AstConstraint* const constrp, AstVarRef* rootVarRefp,
                                 const std::vector<AstVar*>& newPath, AstClass* targetClassp) {
        // A clone the object's class made from its own rand objects is cloned again directly
        // from them, with the path to them for its rand_mode() gate
        if (m_cloneObjps.count(constrp)) return;
        AstNodeExpr* const objp = buildMemberSelChain(rootVarRefp, newPath);
        if (AstConstraint* const cloneConstrp = cloneObjectConstraint(
                constrp, objp, clonePathPrefix(rootVarRefp, newPath), targetClassp)) {
            addClonedConstraint(targetClassp, cloneConstrp, constrp, objp);
        }
        VL_DO_DANGLING(objp->deleteTree(), objp);
    }

    // Whether dtypep is a fixed-size or dynamic array, or a queue
    static bool isIndexedArray(const AstNodeDType* dtypep) {
        return VN_IS(dtypep, UnpackArrayDType) || VN_IS(dtypep, DynArrayDType)
               || VN_IS(dtypep, QueueDType);
    }
    // Whether varp is a fixed-size or dynamic array, or queue, of class handles, or of
    // fixed-size arrays of them
    static bool isHandleArray(const AstVar* varp) {
        // Elements of inner dynamic arrays or queues are nested accesses, not supported
        const AstNodeDType* dtypep = varp->dtypep()->skipRefp();
        if (!isIndexedArray(dtypep)) return false;
        dtypep = dtypep->subDTypep()->skipRefp();
        while (VN_IS(dtypep, UnpackArrayDType)) dtypep = dtypep->subDTypep()->skipRefp();
        return VN_IS(dtypep, ClassRefDType);
    }
    // Whether refp is a reference to the same member as pathp, through the same objects
    static bool samePath(const AstNodeExpr* refp, const AstNodeExpr* pathp) {
        while (true) {
            const AstMemberSel* const selp = VN_CAST(refp, MemberSel);
            const AstMemberSel* const pathSelp = VN_CAST(pathp, MemberSel);
            if (!selp || !pathSelp) break;
            if (selp->varp() != pathSelp->varp()) return false;
            refp = selp->fromp();
            pathp = pathSelp->fromp();
        }
        const AstVarRef* const varRefp = VN_CAST(refp, VarRef);
        const AstVarRef* const pathRefp = VN_CAST(pathp, VarRef);
        return varRefp && pathRefp && varRefp->varp() == pathRefp->varp();
    }

    // Clone the constraints of the objects in rand handle array arrRefp into targetClassp
    void cloneElementConstraints(AstNodeExpr* arrRefp, const std::string& prefix,
                                 AstClass* targetClassp) {
        // An array referenced by targetClassp's constraints is solved by targetClassp, not by
        // randomize() of each object, so the objects' constraints are solved there too
        // (IEEE 1800-2023 18.5.8), applied to each element by a foreach.
        // arrRefp is a reference to the array (isHandleArray) of this or of a member
        // object.
        const AstMemberSel* const arrSelp = VN_CAST(arrRefp, MemberSel);
        AstVar* const arrVarp = arrSelp ? arrSelp->varp() : VN_AS(arrRefp, VarRef)->varp();
        const AstClassRefDType* const elemDtp
            = VN_AS(RandomizeUtil::arrayElementDTypep(arrVarp->dtypep()), ClassRefDType);
        // Not counting the size, which is a separate solver variable
        const bool referenced
            = targetClassp->existsMember([&](const AstClass*, const AstConstraint* constrp) {
                  return constrp->exists([&](const AstNodeExpr* refp) {
                      const AstCMethodHard* const methodp = VN_CAST(refp->backp(), CMethodHard);
                      return samePath(refp, arrRefp)
                             && !(methodp && methodp->method() == VCMethod::DYN_SIZE);
                  });
              });
        if (!referenced) return;
        // A constraint of a derived class overrides the one of the same name of a base class
        // (IEEE 1800-2023 18.5.2), which is visited first
        std::vector<AstConstraint*> constrps;
        std::map<std::string, size_t> nameIndex;
        elemDtp->classp()->foreachMember([&](AstClass* const, AstConstraint* const constrp) {
            const auto pair = nameIndex.emplace(constrp->name(), constrps.size());
            if (pair.second) {
                constrps.push_back(constrp);
            } else {
                constrps[pair.first->second] = constrp;
            }
        });
        FileLine* const fl = arrVarp->fileline();
        for (AstConstraint* const constrp : constrps) {
            // Rand fields that are arrays or objects are not solver variables of the elements
            // (see createWriteVarForClassFields), so constraints on them stay ignored. This
            // includes the constraints the element class has cloned from its own rand objects.
            if (!constrp->itemsp() || constrp->exists([](const AstVarRef* refp) {
                    const AstVar* const varp = refp->varp();
                    const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
                    return varp->isClassMember() && varp->rand().isRandomizable()
                           && (VN_IS(dtypep, ClassRefDType) || dtypep->isNonPackedArray());
                })) {
                continue;
            }
            // An index for each dimension
            std::vector<AstVar*> idxVarps;
            AstNode* idxVarsp = nullptr;
            for (const AstNodeDType* dtypep = arrVarp->dtypep()->skipRefp();
                 isIndexedArray(dtypep); dtypep = dtypep->subDTypep()->skipRefp()) {
                idxVarps.push_back(
                    new AstVar{fl, VVarType::BLOCKTEMP,
                               "__Vi" + (idxVarps.empty() ? "" : cvtToStr(idxVarps.size())),
                               arrVarp->findIntDType()});
                idxVarsp = AstNode::addNext(idxVarsp, idxVarps.back());
            }
            AstNodeExpr* const elemp
                = RandomizeUtil::newElemSelp(fl, arrRefp->cloneTree(false), idxVarps);
            AstConstraint* const cloneConstrp
                = cloneObjectConstraint(constrp, elemp, prefix, targetClassp);
            VL_DO_DANGLING(elemp->deleteTree(), elemp);
            if (!cloneConstrp) {
                VL_DO_DANGLING(idxVarsp->deleteTree(), idxVarsp);
                continue;
            }
            AstNode* const itemsp = cloneConstrp->itemsp()->unlinkFrBackWithNext();
            cloneConstrp->addItemsp(new AstConstraintForeach{
                fl, new AstForeachHeader{fl, arrRefp->cloneTree(false), idxVarsp}, itemsp});
            addClonedConstraint(targetClassp, cloneConstrp, constrp, arrRefp);
        }
    }

    // Class of the objects of class handle varp
    static const AstClass* handleClassp(const AstVar* varp) {
        return VN_AS(varp->dtypep()->skipRefp(), ClassRefDType)->classp();
    }
    // Whether the objects on the path to cloned constraints include one of class classp
    static bool classOnPath(const AstClass* classp, const AstVarRef* rootVarRefp,
                            const std::vector<AstVar*>& path, const AstClass* targetClassp) {
        // Rand handles may form a cycle (IEEE 1800-2023 18.4 does not forbid it), so the
        // constraints of objects reached again through the cycle are not cloned, which
        // would not terminate
        if (classp == targetClassp || classp == handleClassp(rootVarRefp->varp())) return true;
        for (const AstVar* const varp : path) {
            if (classp == handleClassp(varp)) return true;
        }
        return false;
    }

    // Clone constraints from nested rand class members
    void cloneNestedConstraintsRecurse(AstVarRef* rootVarRefp, AstClass* classp,
                                       const std::vector<AstVar*>& pathToClass,
                                       AstClass* targetClassp) {
        // Including inherited members
        classp->foreachMember([&](AstClass* const, AstVar* const memberVarp) {
            if (!memberVarp->rand().isRandomizable()) return;
            const AstClassRefDType* const memberClassRefp
                = VN_CAST(memberVarp->dtypep()->skipRefp(), ClassRefDType);
            // Others are randomized by their own randomize()
            if (memberClassRefp && !memberVarp->globalConstrained()) return;
            std::vector<AstVar*> newPath = pathToClass;
            newPath.push_back(memberVarp);
            if (!memberClassRefp) {
                if (!isHandleArray(memberVarp)) return;
                AstNodeExpr* const arrRefp = buildMemberSelChain(rootVarRefp, newPath);
                cloneElementConstraints(arrRefp, clonePathPrefix(rootVarRefp, newPath),
                                        targetClassp);
                VL_DO_DANGLING(arrRefp->deleteTree(), arrRefp);
                return;
            }

            AstClass* nestedClassp = memberClassRefp->classp();
            if (classOnPath(nestedClassp, rootVarRefp, pathToClass, targetClassp)) return;

            // Replace all variable references inside the cloned constraint with proper
            // member selections
            nestedClassp->foreachMember(
                [&](AstClass* const containingClassp, AstConstraint* const constrp) {
                    processNestedConstraint(constrp, rootVarRefp, newPath, targetClassp);
                });
            cloneNestedConstraintsRecurse(rootVarRefp, nestedClassp, newPath, targetClassp);
        });
    }

    // Get randomized variables from (std::)randomize() arguments
    // and mark AstNodeModule nodes in which they are defined
    void handleRandomizeArgument(AstNodeExpr* exprp, const AstNodeExpr* const fromp,
                                 const bool stdRandomize) {
        // IEEE 1800-2023 18.11: "Arguments are limited to the names of properties
        // of the calling object; expressions are not allowed."
        // However, for compatibility with other simulators, we support complex
        // expressions like obj.member[idx].field in inline randomize().
        // Stop at the target object, 'fromp' if a method call.
        while (exprp && !(fromp && V3Randomize::isRandomizeTarget(exprp, fromp))) {
            AstVar* randVarp = nullptr;
            if (AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel)) {
                randVarp = memberSelp->varp();
                exprp = memberSelp->fromp();
            } else if (AstArraySel* const arraySelp = VN_CAST(exprp, ArraySel)) {
                exprp = arraySelp->fromp();
                continue;  // Skip ArraySel, continue traversing
            } else if (AstStructSel* const structSelp = VN_CAST(exprp, StructSel)) {
                exprp = structSelp->fromp();
                continue;  // Skip StructSel, continue traversing
            } else if (AstCMethodHard* const methodp = VN_CAST(exprp, CMethodHard)) {
                exprp = methodp->fromp();
                continue;
            } else if (AstVarRef* const varrefp = VN_CAST(exprp, VarRef)) {
                randVarp = varrefp->varp();
                varrefp->user1(true);
                varrefp->access(VAccess::READWRITE);
                exprp = nullptr;
            } else {
                // All invalid and unsupported expressions should be caught in V3Width
                exprp->v3fatalSrc("Unexpected expression type in randomize() argument");
            }
            UASSERT_OBJ(randVarp, exprp, "No rand variable found");
            AstNode* backp = randVarp;
            while (backp && !VN_IS(backp, NodeModule)) backp = backp->backp();
            if (stdRandomize) {
                UASSERT_OBJ(backp, randVarp, "No class or module found for rand variable");
                backp->user1(IS_STD_RANDOMIZED);
            } else {
                // Inline randomized then
                UASSERT_OBJ(VN_IS(backp, Class), randVarp,
                            "No class found for inline randomized variable");
                RandomizeMode randMode = {};
                randMode.usesMode = true;
                randVarp->user1(randMode.asUQuad);
                backp->user1(IS_RANDOMIZED_INLINE);
            }
        }
    }

    // VISITORS
    void visit(AstClass* nodep) override {
        VL_RESTORER(m_classp);
        VL_RESTORER(m_modp);
        m_modp = m_classp = nodep;
        m_classps.push_back(nodep);
        iterateChildrenConst(nodep);
        if (nodep->extendsp()) {
            // Record derived class for inheritance hierarchy tracking
            const AstClass* const basep = nodep->extendsp()->classp();
            m_baseToDerivedMap[basep].push_back(nodep);
        }
    }
    void visit(AstNodeStmt* nodep) override {
        VL_RESTORER(m_stmtp);
        m_stmtp = nodep;
        iterateChildren(nodep);
        if (!nodep->backp()) VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (nodep->classOrPackagep() && nodep->classOrPackagep()->name() == "std")
            m_stdRandCallp = nodep;
        iterateChildrenConst(nodep);
        if (nodep->name() == "rand_mode") {
            AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall);
            AstNodeExpr* const fromp = methodCallp ? methodCallp->fromp() : nullptr;
            bool valid = true;
            AstVar* const elemArrVarp = randModeElemArrayp(fromp);
            const bool elemMode
                = elemArrVarp && elemArrVarp->isRand() && !elemArrVarp->lifetime().isStatic();
            if (elemMode) {
                m_elemModeArrays.insert(elemArrVarp);
            } else if (elemArrVarp && !elemArrVarp->isRand()
                       && !VN_IS(fromp->dtypep()->skipRefp(), ClassRefDType)) {
                nodep->v3error("Cannot call 'rand_mode()' on element of non-random array "
                               << elemArrVarp->prettyNameQ() << " (IEEE 1800-2023 18.8)");
                valid = false;
            } else if (VN_IS(fromp, ArraySel)) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: 'rand_mode()' on unpacked array element");
                valid = false;
            } else if (VN_IS(fromp, AssocSel) || VN_IS(fromp, WildcardSel)) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: 'rand_mode()' on associative array element");
                valid = false;
            } else if (VN_IS(fromp, StructSel)) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: 'rand_mode()' on unpacked struct element");
                valid = false;
            } else if (VN_IS(fromp, Sel)) {
                nodep->v3error("Cannot call 'rand_mode()' on packed array element");
                valid = false;
            } else if (AstCMethodHard* const atp = VN_CAST(fromp, CMethodHard)) {
                if (atp->method() == VCMethod::ARRAY_AT) {
                    nodep->v3warn(E_UNSUPPORTED,
                                  "Unsupported: 'rand_mode()' on dynamic array element");
                } else {
                    nodep->v3warn(E_UNSUPPORTED,
                                  "Unsupported: 'rand_mode()' on queue element indexed from '$'");
                }
                valid = false;
            }
            if (!nodep->argsp() && VN_IS(nodep->backp(), StmtExpr)
                && !nodep->backp()->fileline()->warnIsOff(V3ErrorCode::IGNOREDRETURN)) {
                nodep->v3warn(
                    IGNOREDRETURN,
                    "Ignoring return value of non-void function (IEEE 1800-2023 13.4.1)");
                valid = false;
            }
            if (valid) {
                const RandModeTarget randModeTarget = RandModeTarget::get(fromp, m_classp);
                if ((!randModeTarget.receiverp || !randModeTarget.receiverp->isRand())
                    && !nodep->argsp()) {
                    nodep->v3error(
                        "Cannot call 'rand_mode()' as a function on non-random variable");
                    valid = false;
                } else if (!randModeTarget.classp) {
                    nodep->v3error("Cannot call 'rand_mode()' on non-random, non-class variable");
                    valid = false;
                } else if (nodep->argsp() && !VN_IS(nodep->backp(), StmtExpr)) {
                    nodep->v3error("'rand_mode()' with arguments cannot be called as a function");
                    valid = false;
                } else if (elemMode) {
                    // Element modes are kept per array, not in the variable's mode slot
                } else if (randModeTarget.receiverp && randModeTarget.receiverp->isRand()) {
                    // Called on a rand member variable
                    RandomizeMode randMode = {};
                    randMode.usesMode = true;
                    randModeTarget.receiverp->user1(randMode.asUQuad);
                } else {
                    // Called on 'this' or a non-rand class instance
                    randModeTarget.classp->foreachMember([&](AstClass*, AstVar* varp) {
                        if (!varp->isRand()) return;
                        RandomizeMode randMode = {};
                        randMode.usesMode = true;
                        varp->user1(randMode.asUQuad);
                    });
                }
            }
            if (!valid) {
                if (!nodep->argsp() && !VN_IS(nodep->backp(), StmtExpr)) {
                    nodep->replaceWith(new AstConst{nodep->fileline(), 0});
                    VL_DO_DANGLING(nodep->deleteTree(), nodep);
                } else {
                    m_stmtp->unlinkFrBack();
                }
            }
            return;
        }

        if (nodep->name() == "constraint_mode") {
            bool valid = true;
            if (nodep->argsp() && !VN_IS(nodep->backp(), StmtExpr)) {
                nodep->v3error(
                    "'constraint_mode()' with arguments cannot be called as a function");
                valid = false;
            } else if (!nodep->argsp() && VN_IS(nodep->backp(), StmtExpr)
                       && !nodep->backp()->fileline()->warnIsOff(V3ErrorCode::IGNOREDRETURN)) {
                nodep->v3warn(
                    IGNOREDRETURN,
                    "Ignoring return value of non-void function (IEEE 1800-2023 13.4.1)");
                valid = false;
            }
            AstConstraint* constrp = nullptr;
            AstClass* classp = m_classp;
            if (const AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall)) {
                if (const AstConstraintRef* const constrRefp
                    = VN_CAST(methodCallp->fromp(), ConstraintRef)) {
                    constrp = constrRefp->constrp();
                    if (constrRefp->fromp()) classp = VN_AS(constrRefp->classOrPackagep(), Class);
                } else if (AstClassRefDType* classRefDtp
                           = VN_CAST(methodCallp->fromp()->dtypep()->skipRefp(), ClassRefDType)) {
                    classp = classRefDtp->classp();
                } else {
                    nodep->v3error("Cannot call 'constraint_mode()' on a non-class variable");
                    valid = false;
                }
            }
            if (!nodep->argsp() && !constrp) {
                nodep->v3error("Cannot call 'constraint_mode()' as a function on a variable");
                valid = false;
            }
            if (valid) {
                RandomizeMode constraintMode = {};
                constraintMode.usesMode = true;
                if (constrp) {
                    constrp->user1(constraintMode.asUQuad);
                } else {
                    classp->foreachMember([=](AstClass*, AstConstraint* constrp) {
                        constrp->user1(constraintMode.asUQuad);
                    });
                }
            } else {
                if (!nodep->argsp() && !VN_IS(nodep->backp(), StmtExpr)) {
                    nodep->replaceWith(new AstConst{nodep->fileline(), 0});
                    VL_DO_DANGLING(nodep->deleteTree(), nodep);
                } else {
                    m_stmtp->unlinkFrBack();
                }
            }
            return;
        }

        if (nodep->name() != "randomize") {
            // Propagate user1 from children (same pattern as visit(AstNodeExpr*))
            if (m_constraintExprGenp || m_inStdWith) {
                for (AstNode* stmtp = nodep->taskp()->stmtsp(); stmtp; stmtp = stmtp->nextp()) {
                    const AstVar* const portp = VN_CAST(stmtp, Var);
                    if (portp && portp->isWritable()) {
                        nodep->v3error("Function " << nodep->prettyNameQ()
                                                   << " called in constraint has output or ref"
                                                      " argument "
                                                   << portp->prettyNameQ()
                                                   << " (IEEE 1800-2023 18.5.11)");
                        break;
                    }
                }
                // Only the arguments decide whether a call depends on rand variables. The object
                // it's called on doesn't count, so a.f() isn't marked just because 'a' is rand
                for (AstNode* const argp : nodep->argspList()) {
                    if (argp->user1()) {
                        nodep->user1(true);
                        break;
                    }
                }
            }
            return;
        }
        AstClass* classp = m_classp;
        if (const AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall)) {
            if (const AstClassRefDType* const classRefp
                = VN_CAST(methodCallp->fromp()->dtypep()->skipRefp(), ClassRefDType)) {
                classp = classRefp->classp();
            }
        }
        if (classp) {
            if (!classp->user1()) classp->user1(IS_RANDOMIZED);
            markMembers(classp);
        }
        if (nodep->classOrPackagep()->name() == "std") {
            m_stdRandCallp = nullptr;
            for (AstArg* const argp : nodep->argspList()) {
                handleRandomizeArgument(argp->exprp(), nullptr, true);
            }
            return;
        }
        if (nodep->withp()) markSelectedHandles(nodep->withp());
        for (AstArg* const argp : nodep->argspList()) {
            // randomize(null): handle before IS_RANDOMIZED_INLINE so the
            // check-only path does not allocate unused __Vrandmode slots.
            if (const AstConst* const constp = VN_CAST(argp->exprp(), Const)) {
                UASSERT_OBJ(constp->num().isNull(), constp,
                            "Non-null AstConst arg to randomize() should have been "
                            "rejected by V3Width");
                continue;
            }
            classp->user1(IS_RANDOMIZED_INLINE);
            const AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall);
            handleRandomizeArgument(argp->exprp(), methodCallp ? methodCallp->fromp() : nullptr,
                                    false);
        }
        // Re-mark members after the class became inline-randomized above.
        if (classp && classp->user1() == IS_RANDOMIZED_INLINE) markMembers(classp);
    }
    void visit(AstConstraintUnique* nodep) override {
        VL_RESTORER(m_stmtp);
        VL_RESTORER(m_constraintExprGenp);
        m_stmtp = nodep;
        m_constraintExprGenp = nodep;
        iterateChildren(nodep);
        if (!nodep->backp()) VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstConstraintExpr* nodep) override {
        VL_RESTORER(m_constraintExprGenp);
        m_constraintExprGenp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstConstraintIf* nodep) override {
        {
            VL_RESTORER(m_constraintExprGenp);
            m_constraintExprGenp = nodep;
            iterateConst(nodep->condp());
        }
        iterateAndNextConstNull(nodep->thensp());
        iterateAndNextConstNull(nodep->elsesp());
    }
    void visit(AstNodeVarRef* nodep) override {
        if (!m_constraintExprGenp) return;

        if (nodep->varp()->lifetime().isStatic()) m_staticRefs.emplace(nodep);

        // In obj.randomize() with, linking made obj's members MemberSels of the LambdaArgRef,
        // and V3Width turned the static ones into VarRefs of obj's class. Any other reference
        // names a variable in the caller's scope (IEEE 1800-2023 18.7), which is a state value
        // even if declared rand.
        const bool callerVar = m_withClassp
                               && !(nodep->varp()->lifetime().isStatic()
                                    && AstClass::isClassExtendedFrom(
                                        m_withClassp, VN_CAST(nodep->classOrPackagep(), Class)));
        // Mark as randomizable if: rand-declared, or listed in std::randomize() args
        if (nodep->varp()->rand().isRandomizable() && !(m_inStdWith && m_stdRandCallp)
            && !callerVar) {
            nodep->user1(true);
        } else if (isStdRandomizeArg(nodep)) {
            nodep->user1(true);
        }
    }
    void visit(AstMemberSel* nodep) override {
        if (!m_constraintExprGenp) return;
        iterateChildrenConst(nodep);
        const bool randObject = nodep->fromp()->user1() || VN_IS(nodep->fromp(), LambdaArgRef);
        const bool randMember = nodep->varp()->rand().isRandomizable();
        const bool inStdWith = m_inStdWith && m_stdRandCallp;
        if (randObject && randMember && !inStdWith) {
            nodep->user1(true);
        } else if (isStdRandomizeArg(nodep)) {
            nodep->user1(true);
            // Mark parent object for constraint expression visitor
            if (VN_IS(nodep->fromp(), VarRef)) nodep->fromp()->user1(true);
        } else if (RandomizeUtil::randIndexSelp(nodep->fromp(), isMarkedRandIndex)) {
            // A member of an element of a non-random array selected by a random index
            nodep->user1(true);
        }

        if (m_withp) {
            AstNode* backp = m_withp;
            while (backp->backp()) {
                if (const AstMethodCall* const callp = VN_CAST(backp, MethodCall)) {
                    AstClassRefDType* classdtypep
                        = VN_AS(callp->fromp()->dtypep()->skipRefp(), ClassRefDType);
                    nodep->user2p(classdtypep->classp());
                    break;
                }
                backp = backp->backp();
            }
        } else {
            nodep->user2p(m_modp);
        }
    }
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        m_modp = nodep;
        iterateChildrenConst(nodep);
    }
    void visit(AstNodeFTask* nodep) override {
        nodep->user2p(m_modp);
        iterateChildrenConst(nodep);
    }
    void visit(AstVar* nodep) override {
        nodep->user2p(m_modp);
        if (nodep->rand().isRandomizable()) {
            checkRandTypeEligibility(nodep, nodep->dtypep(), nodep->rand().isRandC());
        }
        iterateChildrenConst(nodep);
    }
    void visit(AstWith* nodep) override {
        VL_RESTORER(m_withp);
        VL_RESTORER(m_withClassp);
        m_withp = nodep;
        if (const AstMethodCall* const callp = VN_CAST(nodep->backp(), MethodCall)) {
            m_withClassp = VN_AS(callp->fromp()->dtypep()->skipRefp(), ClassRefDType)->classp();
        }
        if (m_stdRandCallp && nodep == m_stdRandCallp->withp()) m_inStdWith = true;
        iterateChildrenConst(nodep);
        m_inStdWith = false;
        // So a method of a state array is random if its 'with' is, as in 'sum() with (item * r)'
        if (m_constraintExprGenp) nodep->user1(nodep->exprp()->user1());
    }

    // True if opp depends on the value of a rand variable
    static bool dependsOnRandValue(AstNode* opp) {
        // A class handle is not a solver variable, only its rand members are (see
        // visit(AstMemberSel)), so e.g. a 'handle != null' guard is evaluated as state. But a
        // handle selected by a random index, from a random array or not, depends on the index.
        if (!opp || !opp->user1()) return false;
        if (!opp->isClassHandleValue()) return true;
        for (AstNode* curp = opp; curp; curp = curp->op1p()) {
            if (const AstNodeSel* const selp = VN_CAST(curp, NodeSel)) {
                if (selp->bitp()->user1()) return true;
            } else if (const AstCMethodHard* const methodp = VN_CAST(curp, CMethodHard)) {
                if (methodp->method() == VCMethod::ARRAY_AT && methodp->pinsp()->user1()) {
                    return true;
                }
            } else if (!VN_IS(curp, MemberSel) && !VN_IS(curp, StructSel)) {
                return false;
            }
        }
        return false;
    }
    void visit(AstNodeExpr* nodep) override {
        iterateChildrenConst(nodep);
        if (!m_constraintExprGenp && !m_inStdWith) return;
        nodep->user1(isStdRandomizeArg(nodep) || dependsOnRandValue(nodep->op1p())
                     || dependsOnRandValue(nodep->op2p()) || dependsOnRandValue(nodep->op3p())
                     || dependsOnRandValue(nodep->op4p()));
    }
    void visit(AstArg* nodep) override {
        iterateChildrenConst(nodep);
        if (!m_constraintExprGenp && !m_inStdWith) return;
        nodep->user1(dependsOnRandValue(nodep->exprp()));
    }

    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    RandomizeMarkVisitor(AstNode* nodep, ClonedConstraints& cloneObjps,
                         std::unordered_set<AstVar*>& elemModeArrays)
        : m_cloneObjps{cloneObjps}
        , m_elemModeArrays{elemModeArrays} {
        iterateConst(nodep);
        markAllDerived();
        cloneMemberConstraints();
        setPackageRefs();
    }
    ~RandomizeMarkVisitor() override = default;
};

enum class CaptureMode : uint8_t {
    CAP_NO = 0x0,
    CAP_VALUE = 0x01,
    CAP_THIS = 0x02,
    CAP_F_SET_CLASSORPACKAGEP = 0x4,
    CAP_F_XREF = 0x8
};
CaptureMode operator|(CaptureMode a, CaptureMode b) {
    return static_cast<CaptureMode>(static_cast<uint8_t>(a) | static_cast<uint8_t>(b));
}
CaptureMode operator&(CaptureMode a, CaptureMode b) {
    return static_cast<CaptureMode>(static_cast<uint8_t>(a) & static_cast<uint8_t>(b));
}
CaptureMode mode(CaptureMode a) { return a & static_cast<CaptureMode>(0x3); }
bool hasFlags(CaptureMode a, CaptureMode flags) {
    return ((static_cast<uint8_t>(a) & 0xc & static_cast<uint8_t>(flags))
            == static_cast<uint8_t>(flags));
}

class CaptureVisitor final : public VNVisitor {
    AstArg* m_argsp = nullptr;  // Original references turned into arguments
    AstNodeModule* m_callerp;  // Module of the outer context (for capturing `this`)
    AstClass* m_targetp;  // Module of inner context (for symbol lookup)
    std::map<const AstVar*, AstVar*> m_varCloneMap;  // Map original var nodes to their clones
    std::set<AstNode*> m_ignore;  // Nodes to ignore for capturing
    std::set<const AstVar*> m_constraintIterators;  // All with-block foreach index variables
    AstVar* m_thisp = nullptr;  // Variable for outer context's object, if necessary
    bool m_thisIsTarget = false;  // True when the caller's 'this' is the randomized object

    // METHODS

    bool captureVariable(FileLine* const fileline, AstNodeVarRef* varrefp, AstVar*& varp) {
        auto it = m_varCloneMap.find(varrefp->varp());
        if (it == m_varCloneMap.end()) {
            AstVar* const newVarp = varrefp->varp()->cloneTree(false);
            newVarp->fileline(fileline);
            newVarp->varType(VVarType::BLOCKTEMP);
            newVarp->funcLocal(true);
            newVarp->direction(VDirection::INPUT);
            newVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_varCloneMap.emplace(varrefp->varp(), newVarp);
            varp = newVarp;
            return true;
        }
        varp = it->second;
        return false;
    }

    template <typename T_Node>
    void fixupClassOrPackage(AstNode* memberp, T_Node refp) {
        AstNodeModule* const declClassp = VN_AS(memberp->user2p(), NodeModule);
        if (declClassp != m_targetp) refp->classOrPackagep(declClassp);
    }

    template <typename T_Node>
    bool isReferenceToInnerMember(T_Node nodep) {
        return VN_IS(nodep->fromp(), LambdaArgRef);
    }

    AstVar* importThisp(FileLine* fl) {
        if (!m_thisp) {
            AstClassRefDType* const refDTypep
                = new AstClassRefDType{fl, VN_AS(m_callerp, Class), nullptr};
            v3Global.rootp()->typeTablep()->addTypesp(refDTypep);
            m_thisp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vthis", refDTypep};
            m_thisp->funcLocal(true);
            m_thisp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_thisp->direction(VDirection::INPUT);
            m_argsp = AstNode::addNext(m_argsp, new AstArg{fl, "", new AstThisRef{fl, refDTypep}});
        }
        return m_thisp;
    }

    AstVar* getVar(AstVar* const varp) const {
        const auto it = m_varCloneMap.find(varp);
        if (it == m_varCloneMap.end()) return nullptr;
        if (it->second->isStdRandomizeArg()) return nullptr;
        return it->second;
    }

    CaptureMode getVarRefCaptureMode(AstNodeVarRef* varRefp) {
        AstNodeModule* const varModp = VN_AS(varRefp->varp()->user2p(), NodeModule);
        AstClass* const varClassp = VN_CAST(varModp, Class);
        AstClass* const callerClassp = VN_CAST(m_callerp, Class);

        const bool callerIsClass = callerClassp;
        const bool refIsXref = VN_IS(varRefp, VarXRef);
        const bool varIsFuncLocal = varRefp->varp()->isFuncLocal();
        const bool varHasAutomaticLifetime = varRefp->varp()->lifetime().isAutomatic();
        const bool varIsFieldOfCaller = AstClass::isClassExtendedFrom(callerClassp, varClassp);
        const bool varIsParam = varRefp->varp()->isParam();
        const bool varIsConstraintIterator = m_constraintIterators.count(varRefp->varp());
        if (refIsXref) return CaptureMode::CAP_VALUE | CaptureMode::CAP_F_XREF;
        if (varIsConstraintIterator) return CaptureMode::CAP_NO;
        if (varIsFuncLocal && varHasAutomaticLifetime) return CaptureMode::CAP_VALUE;
        if (varIsParam) return CaptureMode::CAP_VALUE;
        // Static var in function (will not be inlined, because it's in class)
        if (callerIsClass && varIsFuncLocal) return CaptureMode::CAP_VALUE;
        if (varClassp && varRefp->varp()->lifetime().isStatic()) {
            // A static member is not reached through 'this'. One of the class the randomize
            // function is created in, or of a base, is referenced directly, which keeps the
            // object's static rand members random (IEEE 1800-2023 18.4). Any other is captured
            // by value.
            const AstClass* const funcClassp = m_targetp ? m_targetp : callerClassp;
            if (AstClass::isClassExtendedFrom(funcClassp, varClassp)) return CaptureMode::CAP_NO;
            return CaptureMode::CAP_VALUE;
        }
        if (callerIsClass && varIsFieldOfCaller) return CaptureMode::CAP_THIS;
        UASSERT_OBJ(!callerIsClass, varRefp, "Invalid reference?");
        return CaptureMode::CAP_VALUE;
    }

    void captureRefByValue(AstNodeVarRef* nodep, CaptureMode capModeFlags) {
        AstVar* newVarp;
        const bool newCapture = captureVariable(nodep->fileline(), nodep, newVarp /*ref*/);
        AstNodeVarRef* const newVarRefp = newCapture ? nodep->cloneTree(false) : nullptr;
        if (!hasFlags(capModeFlags, CaptureMode::CAP_F_SET_CLASSORPACKAGEP)) {
            // Keeping classOrPackagep will cause a broken link after inlining
            nodep->classOrPackagep(nullptr);  // AstScope will figure this out
        }
        nodep->varp(newVarp);
        if (!newCapture) return;
        if (hasFlags(capModeFlags, CaptureMode::CAP_F_XREF)) {
            AstVarRef* const notXVarRefp
                = new AstVarRef{nodep->fileline(), newVarp, VAccess::READ};
            notXVarRefp->classOrPackagep(nodep->classOrPackagep());
            nodep->replaceWith(notXVarRefp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            nodep = notXVarRefp;
        }
        m_ignore.emplace(nodep);
        m_argsp = AstNode::addNext(m_argsp, new AstArg{nodep->fileline(), "", newVarRefp});
    }

    void captureRefByThis(AstNodeVarRef* nodep, CaptureMode /*capModeFlags*/) {
        AstVar* const thisp = importThisp(nodep->fileline());
        AstVarRef* const thisRefp = new AstVarRef{nodep->fileline(), thisp, nodep->access()};
        // A caller variable is not the object's, even when the classes match
        thisRefp->user1(nodep->user1());
        m_ignore.emplace(thisRefp);
        AstMemberSel* const memberSelp
            = new AstMemberSel{nodep->fileline(), thisRefp, nodep->varp()};
        // Propagate random-dependence marking; forcing it on read-only operands
        // would route them through the solver write path.
        if (!m_targetp && nodep->user1()) memberSelp->user1(true);
        // Only then is a member of the caller also a member of the randomized object
        if (m_thisIsTarget) memberSelp->user2p(m_targetp);
        nodep->replaceWith(memberSelp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        m_ignore.emplace(memberSelp);
    }

    // VISITORS

    void visit(AstConstraintForeach* const nodep) override {
        // All header indices are local, including later and omitted dimensions.
        for (const AstNode* elemp = nodep->headerp()->elementsp(); elemp; elemp = elemp->nextp()) {
            if (const AstVar* const varp = VN_CAST(elemp, Var)) m_constraintIterators.insert(varp);
        }
        iterateChildren(nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (m_ignore.count(nodep)) return;
        m_ignore.emplace(nodep);
        UASSERT_OBJ(nodep->varp(), nodep, "Variable unlinked");
        if (nodep->varp()->isStdRandomizeArg()) return;
        const CaptureMode capMode = getVarRefCaptureMode(nodep);
        if (mode(capMode) == CaptureMode::CAP_NO) return;
        if (mode(capMode) == CaptureMode::CAP_VALUE) captureRefByValue(nodep, capMode);
        if (mode(capMode) == CaptureMode::CAP_THIS) captureRefByThis(nodep, capMode);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (m_ignore.count(nodep)) {
            iterateChildren(nodep);
            return;
        }
        m_ignore.emplace(nodep);
        UASSERT_OBJ(nodep->taskp(), nodep, "Task unlinked");
        // We assume that constraint targets are not referenced this way.
        if (VN_IS(nodep, MethodCall) || VN_IS(nodep, New)) {
            m_ignore.emplace(nodep);
            iterateChildren(nodep);
            return;
        }
        iterateChildren(nodep);
        AstClass* const classp = VN_CAST(nodep->taskp()->user2p(), Class);
        if ((classp == m_callerp) && VN_IS(m_callerp, Class)) {
            AstArg* const argsp = nodep->argsp();
            if (argsp) argsp->unlinkFrBackWithNext();
            AstVar* const thisp = importThisp(nodep->fileline());
            AstVarRef* const thisRefp = new AstVarRef{
                nodep->fileline(), thisp, nodep->isPure() ? VAccess::READ : VAccess::READWRITE};
            m_ignore.emplace(thisRefp);
            AstMethodCall* const methodCallp
                = new AstMethodCall{nodep->fileline(), thisRefp, thisp->name(), argsp};
            methodCallp->taskp(nodep->taskp());
            methodCallp->dtypep(nodep->dtypep());
            methodCallp->user1(nodep->user1());
            nodep->replaceWith(methodCallp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            m_ignore.emplace(methodCallp);
        }
    }
    void visit(AstMemberSel* nodep) override {
        if (!isReferenceToInnerMember(nodep)) {
            iterateChildren(nodep);
            return;
        }
        AstVarRef* const varRefp
            = new AstVarRef{nodep->fileline(), nodep->varp(), nodep->access()};
        fixupClassOrPackage(nodep->varp(), varRefp);
        varRefp->user1(nodep->user1());
        nodep->replaceWith(varRefp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        m_ignore.emplace(varRefp);
    }
    void visit(AstMethodCall* nodep) override {
        if (!isReferenceToInnerMember(nodep) || m_ignore.count(nodep)) {
            iterateChildren(nodep);
            return;
        }
        AstArg* const argsp = nodep->argsp();
        if (argsp) argsp->unlinkFrBackWithNext();
        AstNodeFTaskRef* taskRefp = nullptr;
        if (AstTask* const taskp = VN_CAST(nodep->taskp(), Task)) {
            taskRefp = new AstTaskRef{nodep->fileline(), taskp, argsp};
        } else if (AstFunc* const taskp = VN_CAST(nodep->taskp(), Func)) {
            taskRefp = new AstFuncRef{nodep->fileline(), taskp, argsp};
        } else {
            nodep->v3fatalSrc("Node needs to point to regular method");
        }
        fixupClassOrPackage(nodep->taskp(), taskRefp);
        taskRefp->user1(nodep->user1());
        nodep->replaceWith(taskRefp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        m_ignore.emplace(taskRefp);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit CaptureVisitor(AstNode* const nodep, AstNodeModule* callerp, AstClass* const targetp,
                            bool thisIsTarget = false)
        : m_callerp{callerp}
        , m_targetp{targetp}
        , m_thisIsTarget{thisIsTarget} {
        iterateAndNextNull(nodep);
    }

    // PUBLIC METHODS

    AstArg* getArgs() const { return m_argsp; }
    AstVar* getThisp() const { return m_thisp; }

    void addFunctionArguments(AstNodeFTask* funcp) const {
        for (AstArg* argp = getArgs(); argp; argp = VN_AS(argp->nextp(), Arg)) {
            if (AstNodeVarRef* varrefp = VN_CAST(argp->exprp(), NodeVarRef)) {
                if ((varrefp->classOrPackagep() == m_callerp) || VN_IS(varrefp, VarXRef)) {
                    // Keeping classOrPackagep will cause a broken link after inlining
                    varrefp->classOrPackagep(nullptr);
                }
                funcp->addStmtsp(getVar(varrefp->varp()));
            } else {
                UASSERT_OBJ(VN_IS(argp->exprp(), ThisRef), argp->exprp(), "Wrong arg expression");
                funcp->addStmtsp(m_thisp);
            }
        }
    }
};

//######################################################################
// Visitor that defines a randomize method where needed

class RandomizeVisitor final : public VNVisitor {
    // NODE STATE
    // Cleared on Netlist
    //  AstClass::user1()       -> bool.  Set true to indicate needs randomize processing
    //  AstVar::user2p()        -> AstNodeModule*. Pointer to containing module
    //  AstNodeFTask::user2p()  -> AstNodeModule*. Pointer to containing module
    //  AstEnumDType::user2()   -> AstVarRef*. Reference to table with enum values, to clone
    //  AstClass::user2p()      -> AstVar*.  Rand mode state variable
    //  AstVar::user3()         -> bool. Handled in constraints (skipped by __VBasicRand)
    //  AstClass::user4p()      -> AstVar*.  Constraint mode state variable
    //  AstNodeFTaskRef::user4() -> bool.  Processed
    //  Other user3/user4 fields are used by the solver back-end, see V3SolverSmt.cpp
    //  AstMemberSel::user2p()  -> AstNodeModule*. Pointer to containing module
    // VNUser1InUse    m_inuser1;      (Allocated for use in RandomizeMarkVisitor)
    // VNUser2InUse    m_inuser2;      (Allocated for use in RandomizeMarkVisitor)
    const VNUser3InUse m_inuser3;
    const VNUser4InUse m_inuser4;

    // STATE
    V3UniqueNames m_inlineUniqueNames;  // For generating unique function names
    V3UniqueNames m_randArrayUniqueNames{"__Vrandarr"};  // Random array loop indices
    V3UniqueNames m_modeUniqueNames{"__Vmode"};  // For generating unique rand/constraint
                                                 // mode state var names
    V3UniqueNames m_inlineUniqueStdName{"__VStdrand"};
    V3UniqueNames m_uniqueNames;  // Unique names of temporaries, and of blocks holding them
    VMemberMap m_memberMap;  // Member names cached for fast lookup
    AstNodeModule* m_modp = nullptr;  // Current module
    std::unordered_map<AstNodeModule*, AstVar*> m_stdMap;  // Map from module/class to AST Var
    AstNodeFTask* m_ftaskp = nullptr;  // Current function/task
    AstNodeStmt* m_stmtp = nullptr;  // Current statement
    AstDynArrayDType* m_dynarrayDtp = nullptr;  // Dynamic array type (for rand mode)
    int m_randCaseNum = 0;  // Randcase number within a module for var naming
    std::map<std::string, AstCDType*> m_randcDtypes;  // RandC data type deduplication
    AstConstraint* m_constraintp = nullptr;  // Current constraint
    std::unordered_set<const AstClass*> m_visitedClasses;  // Classes visited so far
    std::map<AstClass*, std::pair<bool, bool>>
        m_prePostWrap;  // Per-handle-type pre/post virtual wrapper presence
    // Methods implementing randomize(null), see addRandomizeNullBody
    enum class NullPhase : uint8_t { NONE, ENTRY, PRE, CHECK, POST };
    std::vector<std::tuple<AstClass*, NullPhase, AstFunc*>>
        m_randomizeNullFuncs;  // randomize(null) methods, body added after lowering
    NullPhase m_nullPhase = NullPhase::NONE;  // Building a randomize(null) method
    std::unordered_set<const AstClass*> m_globalOwnerClassps;  // Classes solving sub-objects
    RandModeVars m_modeVars;  // Static rand_mode/constraint_mode state vars per class
    ElemRandModes m_elemModes;  // Per-element rand_mode() state
    std::map<AstClass*, std::vector<AstClass*>> m_derivedClasses;  // Directly derived classes
    const std::unique_ptr<V3SolverLowering> m_solverp;  // Constraint solver lowering

    // METHODS
    AstVar* createStdRandomGenerator(AstNodeModule* const modp) {
        auto it = m_stdMap.find(modp);
        if (it == m_stdMap.end()) {
            AstVar* const stdgenp
                = new AstVar{modp->fileline(), VVarType::MEMBER, "stdrand",
                             modp->findBasicDType(VBasicDTypeKwd::RANDOM_STDGENERATOR)};
            stdgenp->fileline()->warnOff(V3ErrorCode::IMPURE, true);
            modp->addStmtsp(stdgenp);
            m_stdMap.emplace(modp, stdgenp);
            return stdgenp;
        }
        return it->second;
    }
    AstVar* getCreateRandModeVar(AstClass* const classp) {
        if (classp->user2p()) return VN_AS(classp->user2p(), Var);
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getCreateRandModeVar(extendsp->classp());
        }
        AstVar* const randModeVarp = createModeVar(classp, "__Vrandmode");
        classp->user2p(randModeVarp);
        return randModeVarp;
    }
    AstVar* getCreateConstraintModeVar(AstClass* const classp) {
        if (classp->user4p()) return VN_AS(classp->user4p(), Var);
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getCreateConstraintModeVar(extendsp->classp());
        }
        AstVar* const constraintModeVarp = createModeVar(classp, "__Vconstraintmode");
        classp->user4p(constraintModeVarp);
        return constraintModeVarp;
    }
    static AstVar* getConstraintModeVar(AstClass* const classp) {
        return RandModeVars::constraintModeVarp(classp);
    }
    AstVar* getCreateStaticConstraintModeVar(AstClass* const classp) {
        if (AstVar* const staticModeVarp = m_modeVars.staticConstraintModeVarp(classp)) {
            return staticModeVarp;
        }
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getCreateStaticConstraintModeVar(extendsp->classp());
        }
        AstVar* const staticModeVarp = createStaticModeVar(classp, "__Vstaticconstraintmode");
        m_modeVars.addStaticConstraintModeVar(classp, staticModeVarp);
        return staticModeVarp;
    }
    AstVar* getStaticConstraintModeVar(AstClass* const classp) {
        return m_modeVars.staticConstraintModeVarp(classp);
    }
    AstVar* getCreateStaticRandModeVar(AstClass* const classp) {
        if (AstVar* const staticModeVarp = m_modeVars.staticRandModeVarp(classp)) {
            return staticModeVarp;
        }
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getCreateStaticRandModeVar(extendsp->classp());
        }
        AstVar* const staticModeVarp = createStaticModeVar(classp, "__Vstaticrandmode");
        m_modeVars.addStaticRandModeVar(classp, staticModeVarp);
        return staticModeVarp;
    }
    AstVar* getStaticRandModeVar(AstClass* const classp) {
        return m_modeVars.staticRandModeVarp(classp);
    }
    // Get or create the per-element rand_mode state of an array, nullptr if it has none
    AstVar* elemModeVarp(AstVar* const arrVarp) { return m_elemModes.modeVarp(arrVarp); }
    AstVar* createModeVar(AstClass* const classp, const char* const name) {
        FileLine* const fl = classp->fileline();
        if (!m_dynarrayDtp) {
            m_dynarrayDtp = new AstDynArrayDType{
                fl, v3Global.rootp()->typeTablep()->findBitDType()->dtypep()};
            m_dynarrayDtp->dtypep(m_dynarrayDtp);
            v3Global.rootp()->typeTablep()->addTypesp(m_dynarrayDtp);
        }
        // MEMBER, not MODULETEMP, so V3Localize does not localize it into new().
        AstVar* const modeVarp = new AstVar{fl, VVarType::MEMBER, name, m_dynarrayDtp};
        modeVarp->user2p(classp);
        classp->addMembersp(modeVarp);
        return modeVarp;
    }
    AstVar* createStaticModeVar(AstClass* const classp, const char* const name) {
        // Create a static variable that will be shared across all instances.
        // By setting lifetime to STATIC_EXPLICIT, V3Class will move this to the class package.
        FileLine* const fl = classp->fileline();
        if (!m_dynarrayDtp) {
            m_dynarrayDtp = new AstDynArrayDType{
                fl, v3Global.rootp()->typeTablep()->findBitDType()->dtypep()};
            m_dynarrayDtp->dtypep(m_dynarrayDtp);
            v3Global.rootp()->typeTablep()->addTypesp(m_dynarrayDtp);
        }
        AstVar* const modeVarp = new AstVar{fl, VVarType::MODULETEMP, name, m_dynarrayDtp};
        modeVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        // Note: user2p is set to classp here. V3Scope will later update varScopep
        // to point to the package scope when the variable is moved by V3Class.
        modeVarp->user2p(classp);
        classp->addMembersp(modeVarp);
        // Register so findStaticRandModeVar sees it through the already
        // scanned member cache
        m_memberMap.insert(classp, modeVarp);
        return modeVarp;
    }
    void createRandomizeClassVars(AstNetlist* const netlistp) {
        // Defer init to one emission per root with max descendant count;
        // super.new() runs Base ctor before Derived can resize the static array.
        std::map<AstClass*, uint32_t> rootStaticRandModeCount;
        netlistp->foreach([this, &rootStaticRandModeCount](AstClass* const classp) {
            bool hasConstraints = false;
            uint32_t randModeCount = 0;
            uint32_t staticRandModeCount = 0;
            uint32_t constraintModeCount = 0;
            uint32_t staticConstraintModeCount = 0;
            classp->foreachMember([&](AstClass*, AstNode* memberp) {
                // SystemVerilog only allows single inheritance, so we don't need to worry about
                // index overlap. If the index > 0, it's already been set.
                if (AstConstraint* const constrp = VN_CAST(memberp, Constraint)) {
                    hasConstraints = true;
                    RandomizeMode constraintMode = {.asUQuad = memberp->user1()};
                    if (!constraintMode.usesMode) return;
                    if (constraintMode.index == 0) {
                        // Use separate index counters for static vs non-static constraints
                        if (constrp->isStatic()) {
                            constraintMode.index = staticConstraintModeCount++;
                        } else {
                            constraintMode.index = constraintModeCount++;
                        }
                        memberp->user1(constraintMode.asUQuad);
                    } else {
                        if (constrp->isStatic()) {
                            staticConstraintModeCount = constraintMode.index + 1;
                        } else {
                            constraintModeCount = constraintMode.index + 1;
                        }
                    }
                } else if (AstVar* const varp = VN_CAST(memberp, Var)) {
                    RandomizeMode randMode = {.asUQuad = memberp->user1()};
                    if (!randMode.usesMode) return;
                    const bool isStaticVar = varp->lifetime().isStatic();
                    if (randMode.index == 0) {
                        if (isStaticVar) {
                            randMode.index = staticRandModeCount++;
                        } else {
                            randMode.index = randModeCount++;
                        }
                        memberp->user1(randMode.asUQuad);
                    } else {
                        if (isStaticVar) {
                            staticRandModeCount = randMode.index + 1;
                        } else {
                            randModeCount = randMode.index + 1;
                        }
                    }
                }
            });
            // Also account for rand_mode indices from globalConstrained sub-objects.
            // When constraints from sub-objects are flattened into this class's constraint
            // setup functions, the generated code references this->__Vrandmode.at(index).
            // We must ensure this class's __Vrandmode is initialized to cover those indices.
            {
                std::function<void(AstClass*)> findSubObjRandModes = [&](AstClass* subClassp) {
                    subClassp->foreachMember([&](AstClass*, AstNode* subMemberp) {
                        if (AstVar* const subVarp = VN_CAST(subMemberp, Var)) {
                            const RandomizeMode rm = {.asUQuad = subVarp->user1()};
                            if (!rm.usesMode) return;
                            // Static rand vars index into their own class's static
                            // rand mode array, not into the outer __Vrandmode.
                            if (subVarp->lifetime().isStatic()) return;
                            const uint32_t needed = rm.index + 1;
                            if (needed > randModeCount) randModeCount = needed;
                        }
                    });
                };
                classp->foreachMember([&](AstClass*, AstVar* memberVarp) {
                    if (!memberVarp->globalConstrained()) return;
                    const AstNodeDType* const dtypep = memberVarp->dtypep()->skipRefp();
                    const AstClassRefDType* const classRefp = VN_CAST(dtypep, ClassRefDType);
                    if (!classRefp) return;
                    findSubObjRandModes(classRefp->classp());
                });
            }
            if (hasConstraints) m_solverp->prepareClass(classp);
            if (randModeCount > 0) {
                AstVar* const randModeVarp = getCreateRandModeVar(classp);
                makeModeInit(randModeVarp, classp, randModeCount);
            }
            if (constraintModeCount > 0) {
                AstVar* const constraintModeVarp = getCreateConstraintModeVar(classp);
                makeModeInit(constraintModeVarp, classp, constraintModeCount);
            }
            if (staticConstraintModeCount > 0) {
                AstVar* const staticConstraintModeVarp = getCreateStaticConstraintModeVar(classp);
                makeStaticModeInit(staticConstraintModeVarp, classp, staticConstraintModeCount);
            }
            if (staticRandModeCount > 0) {
                getCreateStaticRandModeVar(classp);
                AstClass* rootp = classp;
                while (AstClassExtends* const ep = rootp->extendsp()) rootp = ep->classp();
                uint32_t& slot = rootStaticRandModeCount[rootp];
                if (staticRandModeCount > slot) slot = staticRandModeCount;
            }
        });
        for (const auto& kv : rootStaticRandModeCount) emitRootStaticModeInit(kv.first, kv.second);
    }
    void emitRootStaticModeInit(AstClass* const rootp, const uint32_t count) {
        AstVar* const staticRandModeVarp = m_modeVars.staticRandModeVarp(rootp);
        UASSERT_OBJ(staticRandModeVarp, rootp, "Root must have a static rand-mode var");
        makeStaticModeInit(staticRandModeVarp, rootp, count);
    }
    void makeModeInit(AstVar* modeVarp, AstClass* classp, uint32_t modeCount) {
        AstNodeModule* const modeVarModp = VN_AS(modeVarp->user2p(), NodeModule);
        FileLine* const fl = modeVarp->fileline();
        AstVar* const oldSizeVarp = new AstVar{
            fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__VoldSize"), modeVarp->findUInt32DType()};
        oldSizeVarp->funcLocal(true);
        oldSizeVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        AstCMethodHard* const oldSizep
            = new AstCMethodHard{fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::READ},
                                 VCMethod::DYN_SIZE, nullptr};
        oldSizep->dtypeSetUInt32();
        AstCMethodHard* const dynarrayNewp
            = new AstCMethodHard{fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::WRITE},
                                 VCMethod::DYN_RESIZE, new AstConst{fl, modeCount}};
        dynarrayNewp->dtypeSetVoid();
        AstNodeFTask* const ctorNewp = VN_AS(m_memberMap.findMember(classp, "new"), NodeFTask);
        UASSERT_OBJ(ctorNewp, classp, "No new() in class");
        // Preserve inherited modes set by super.new() and initialize only newly added entries.
        AstNode* const initFirstp = oldSizeVarp;
        initFirstp->addNext(
            new AstAssign{fl, new AstVarRef{fl, oldSizeVarp, VAccess::WRITE}, oldSizep});
        initFirstp->addNext(dynarrayNewp->makeStmt());
        initFirstp->addNext(makeModeSetLoop(
            fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::WRITE}, new AstConst{fl, 1},
            true, new AstVarRef{fl, oldSizeVarp, VAccess::READ}));
        // Prepend init code before user statements in constructor body, but after
        // var declarations and super.new(). This ensures that user's constraint_mode()
        // or rand_mode() calls in the constructor execute after mode arrays are initialized.
        // Pattern from V3LinkDot::addImplicitSuperNewCall.
        for (AstNode* const stmtp : ctorNewp->stmtspList()) {
            if (!VN_IS(stmtp, NodeStmt)) continue;  // Skip var declarations
            if (const AstStmtExpr* const sep = VN_CAST(stmtp, StmtExpr)) {
                if (VN_IS(sep->exprp(), New)) continue;  // Skip super.new()
            }
            // Found first user statement - insert init code before it
            stmtp->addHereThisAsNext(initFirstp);
            return;
        }
        // No user statements (empty constructor or only var decls/super.new)
        ctorNewp->addStmtsp(initFirstp);
    }
    void makeStaticModeInit(AstVar* modeVarp, AstClass* classp, uint32_t modeCount) {
        // For static constraint mode, we need lazy initialization since it's shared across
        // instances. Generate: if (size() == 0) { resize(N); set all to 1; }
        AstNodeModule* const modeVarModp = VN_AS(modeVarp->user2p(), NodeModule);
        FileLine* const fl = modeVarp->fileline();

        // Build the condition: size() == 0
        AstCMethodHard* const sizep
            = new AstCMethodHard{fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::READ},
                                 VCMethod::DYN_SIZE, nullptr};
        sizep->dtypeSetUInt32();
        AstEq* const condp = new AstEq{fl, sizep, new AstConst{fl, 0}};

        // Build the then-block: resize and set all to 1
        AstCMethodHard* const dynarrayNewp
            = new AstCMethodHard{fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::WRITE},
                                 VCMethod::DYN_RESIZE, new AstConst{fl, modeCount}};
        dynarrayNewp->dtypeSetVoid();
        AstNode* const thenStmtsp = dynarrayNewp->makeStmt();
        thenStmtsp->addNext(
            makeModeSetLoop(fl, new AstVarRef{fl, modeVarModp, modeVarp, VAccess::WRITE},
                            new AstConst{fl, 1}, true));

        // Build the if statement
        AstIf* const ifp = new AstIf{fl, condp, thenStmtsp};

        // Add to new() constructor
        AstNodeFTask* const newp = VN_AS(m_memberMap.findMember(classp, "new"), NodeFTask);
        UASSERT_OBJ(newp, classp, "No new() in class");
        newp->addStmtsp(ifp);
    }
    AstNode* makeModeSetLoop(FileLine* const fl, AstNodeExpr* const lhsp, AstNodeExpr* const rhsp,
                             bool inTask, AstNodeExpr* const startp = nullptr) {
        AstVar* const iterVarp = new AstVar{fl, VVarType::BLOCKTEMP, "i", lhsp->findUInt32DType()};
        iterVarp->funcLocal(inTask);
        iterVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        AstCMethodHard* const sizep = new AstCMethodHard{fl, lhsp, VCMethod::DYN_SIZE, nullptr};
        sizep->dtypeSetUInt32();
        AstCMethodHard* const setp
            = new AstCMethodHard{fl, lhsp->cloneTree(false), VCMethod::ARRAY_AT_WRITE,
                                 new AstVarRef{fl, iterVarp, VAccess::READ}};
        setp->dtypeSetUInt32();
        AstNode* const stmtsp = iterVarp;
        stmtsp->addNext(new AstAssign{fl, new AstVarRef{fl, iterVarp, VAccess::WRITE},
                                      startp ? startp : new AstConst{fl, 0}});

        AstLoop* const loopp = new AstLoop{fl};
        stmtsp->addNext(loopp);
        loopp->addStmtsp(new AstLoopTest{
            fl, loopp, new AstLt{fl, new AstVarRef{fl, iterVarp, VAccess::READ}, sizep}});
        loopp->addStmtsp(new AstAssign{fl, setp, rhsp});
        loopp->addStmtsp(new AstAssign{
            fl, new AstVarRef{fl, iterVarp, VAccess::WRITE},
            new AstAdd{fl, new AstConst{fl, 1}, new AstVarRef{fl, iterVarp, VAccess::READ}}});
        return new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), stmtsp, true};
    }
    void addTempVarsp(AstVar* varsp) {
        for (AstVar* varp = varsp; varp; varp = VN_AS(varp->nextp(), Var)) {
            if (m_ftaskp) {
                varp->funcLocal(true);
            } else {
                varp->varType(VVarType::MODULETEMP);
                varp->lifetime(VLifetime::STATIC_EXPLICIT);
            }
        }
        if (!m_ftaskp) {
            m_modp->addStmtsp(varsp);
        } else {
            m_ftaskp->prependStmtsp(varsp);
        }
    }
    AstNodeStmt* wrapIfRandMode(AstClass* classp, AstVar* const varp, AstNodeStmt* stmtp) {
        const RandomizeMode rmode = {.asUQuad = varp->user1()};
        AstVar* const modeVarp = varp->lifetime().isStatic() ? getStaticRandModeVar(classp)
                                                             : RandModeVars::randModeVarp(classp);
        return VN_AS(RandModeVars::wrapIfMode(rmode, modeVarp, stmtp), NodeStmt);
    }
    AstVarRef* enumValueTabRefp(AstEnumDType* const nodep) {
        // Return a reference to a constant table of the values of the given enum. The reference
        // is cached, so the table is built only once.
        if (nodep->user2p()) return VN_AS(nodep->user2p(), VarRef)->cloneTree(false);
        UINFO(9, "Construct enum value table " << nodep);
        AstNodeArrayDType* const vardtypep = new AstUnpackArrayDType{
            nodep->fileline(), nodep->dtypep(),
            new AstRange{nodep->fileline(), static_cast<int>(nodep->itemCount()) - 1, 0}};
        v3Global.rootp()->typeTablep()->addTypesp(vardtypep);
        AstConsArray* const consp = new AstConsArray{nodep->fileline(), vardtypep};
        UASSERT_OBJ(nodep->itemsp(), nodep, "Enum without items");
        uint64_t index = 0;
        for (AstEnumItem* const itemp : nodep->itemspList()) {
            AstConst* const vconstp = VN_AS(itemp->valuep(), Const);
            UASSERT_OBJ(vconstp, nodep, "Enum item without constified value");
            consp->valuep(index++, vconstp->cloneTree(false));
        }
        // Share identical tables via the constant pool
        AstVarRef* const refp = V3ConstPool::find(consp);
        VL_DO_DANGLING(consp->deleteTree(), consp);  // V3ConstPool::find clones it
        pushDeletep(refp);  // Deleted with the visitor - always cloned
        nodep->user2p(refp);
        return refp->cloneTree(false);
    }

    AstCDType* findVlRandCDType(FileLine* const fl, uint64_t items) {
        // For 8 items we need to have a 9 item LFSR so items is max count
        // width(items) = log2(items) + 1
        const std::string type = AstCDType::typeToHold(V3Number::log2bQuad(items) + 1);
        const std::string name = "VlRandC<" + type + ", " + cvtToStr(items) + "ULL>";
        // Create or reuse (to avoid duplicates) randomization object dtype
        const auto pair = m_randcDtypes.emplace(name, nullptr);
        if (pair.second) {
            AstCDType* const newp = new AstCDType{fl, name};
            v3Global.rootp()->typeTablep()->addTypesp(newp);
            pair.first->second = newp;
        }
        return pair.first->second;
    }

    AstVar* newRandcVarsp(AstVar* const varp, AstClass* const classp) {
        // Might be called multiple times on same var, if var is referenced in class extends,
        // If so, each is randomized separately, so the select lands in the extending class

        // If a randc, make a VlRandC object to hold the state
        if (!varp->isRandC()) return nullptr;

        uint64_t items = 0;
        if (AstEnumDType* const enumDtp = VN_CAST(varp->dtypep()->skipRefToEnump(), EnumDType)) {
            items = static_cast<uint64_t>(enumDtp->itemCount());
        } else if (AstBasicDType* const basicp = varp->dtypep()->skipRefp()->basicp()) {
            if (basicp->width() > 32) {
                // Real/chandle/string/event are rejected by type upstream already;
                // an over-width integral type isn't, so still needs its own message.
                if (!V3Error::errorCount()) {
                    varp->v3error("Maximum implemented width for randc is 32 bits, "
                                  << varp->prettyNameQ() << " is " << basicp->width() << " bits");
                }
                varp->rand(VRandAttr::RAND);
                return nullptr;
            }
            items = 1ULL << basicp->width();
        } else if (AstStructDType* const dtp = VN_CAST(varp->dtypep()->skipRefp(), StructDType)) {
            UASSERT_OBJ(!dtp->packed(), dtp, "skipRef should have hidden packed before got here");
            dtp->v3error("Unpacked structs shall not be declared as randc"
                         " (IEEE 1800-2023 18.4)");
            return nullptr;
        } else {
            // Only remaining possibility: an object handle, virtual interface,
            // or unpacked union declared randc -- checkRandTypeEligibility()
            // already rejected each of those with its own error, earlier in
            // this same pass, before newRandcVarsp() ever runs on this var.
            UASSERT_OBJ(V3Error::errorCount(), varp, "Unexpected randc variable dtype");
            return nullptr;
        }
        AstCDType* const newdtp = findVlRandCDType(varp->fileline(), items);
        AstVar* const newp
            = new AstVar{varp->fileline(), VVarType::MEMBER, varp->name() + "__Vrandc", newdtp};
        newp->isInternal(true);
        classp->addMembersp(newp);
        UINFO(9, "created " << varp);
        return newp;
    }
    // Return statements randomizing an std::randomize() argument without constraints
    AstNodeStmt* newBasicStdRandStmtsp(FileLine* const fl, AstVar* const stdrandp,
                                       AstVar* const fvarp, AstNodeExpr* const exprp) {
        AstNodeDType* const dtypep = exprp->dtypep()->skipRefp();
        const AstStructDType* const structp
            = VN_CAST(RandomizeUtil::arrayElementDTypep(dtypep), StructDType);
        if (structp && !structp->packed()) {
            // The runtime randomizes integral values and arrays of them, so recurse into
            // arrays of unpacked structs and into the members
            if (dtypep->isNonPackedArray()) {
                return createArrayForeachLoop(fl, dtypep, exprp, [&](AstNodeExpr* elemp) {
                    return newBasicStdRandStmtsp(fl, stdrandp, fvarp, elemp->cloneTree(false));
                });
            }
            // As for class members (newRandStmtsp), IEEE 1800-2023 18.4: an unpacked struct
            // member is only randomized if its own declaration carries rand/randc. Members
            // the 'with' constraints refer to are randomized by the solver.
            AstNodeStmt* stmtsp = nullptr;
            for (const AstMemberDType* const memberp : structp->memberspList()) {
                if (!memberp->rand().isRandomizable()) continue;
                AstStructSel* const selp
                    = new AstStructSel{fl, exprp->cloneTree(false), memberp->name()};
                selp->dtypep(memberp->subDTypep());
                stmtsp = AstNode::addNextNull(stmtsp,
                                              newBasicStdRandStmtsp(fl, stdrandp, fvarp, selp));
            }
            VL_DO_DANGLING(exprp->deleteTree(), exprp);
            return stmtsp;
        }
        AstCMethodHard* const callp
            = new AstCMethodHard{fl, new AstVarRef{fl, stdrandp, VAccess::READWRITE},
                                 VCMethod::RANDOMIZER_BASIC_STD_RANDOMIZATION, exprp};
        // The runtime masks each element to this width; queue, dynamic and associative array
        // types have no width of their own
        const uint64_t width = RandomizeUtil::arrayElementDTypep(dtypep)->width();
        callp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, width});
        callp->dtypeSetBit();
        return new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE},
                             new AstAnd{fl, new AstVarRef{fl, fvarp, VAccess::READ}, callp}};
    }
    // Return a foreach loop over an array, with newElementStmtsp(element) as the body
    AstNodeStmt*
    createArrayForeachLoop(FileLine* const fl, AstNodeDType* const dtypep, AstNodeExpr* exprp,
                           const std::function<AstNodeStmt*(AstNodeExpr*)>& newElementStmtsp,
                           AstVar* const elemModeVarp = nullptr) {
        AstNodeDType* tempDTypep = dtypep;
        AstVar* randLoopIndxp = nullptr;
        auto createLoopIndex = [&](AstNodeDType* tempDTypep) {
            if (VN_IS(tempDTypep, AssocArrayDType)) {
                return new AstVar{fl, VVarType::VAR, m_randArrayUniqueNames.get(""),
                                  VN_AS(tempDTypep, AssocArrayDType)->keyDTypep()};
            }
            return new AstVar{fl, VVarType::VAR, m_randArrayUniqueNames.get(""),
                              dtypep->findBasicDType(VBasicDTypeKwd::UINT32)};
        };
        AstNodeExpr* tempElementp = nullptr;
        AstNodeExpr* firstIndexp = nullptr;  // Element offset in the outermost dimension
        while (tempDTypep->isNonPackedArray()) {
            AstVar* const newRandLoopIndxp = createLoopIndex(tempDTypep);
            randLoopIndxp = AstNode::addNext(randLoopIndxp, newRandLoopIndxp);
            AstNodeExpr* const tempExprp = tempElementp ? tempElementp : exprp;
            AstVarRef* const tempRefp = new AstVarRef{fl, newRandLoopIndxp, VAccess::READ};
            if (VN_IS(tempDTypep, DynArrayDType)) {
                tempElementp
                    = new AstCMethodHard{fl, tempExprp, VCMethod::ARRAY_AT_WRITE, tempRefp};
            } else if (VN_IS(tempDTypep, UnpackArrayDType)) {
                AstNodeArrayDType* const aryDTypep = VN_CAST(tempDTypep, NodeArrayDType);
                // Adjust the bitp to ensure it covers all possible indices
                tempElementp = new AstArraySel{
                    fl, tempExprp,
                    new AstSel{
                        fl,
                        new AstSub{fl, tempRefp,
                                   new AstConst{fl, static_cast<uint32_t>(aryDTypep->lo())}},
                        new AstConst{fl, 0}, V3Number::log2b(aryDTypep->elementsConst() - 1) + 1}};
            } else if (VN_IS(tempDTypep, AssocArrayDType)) {
                tempElementp = new AstAssocSel{fl, tempExprp, tempRefp};
            } else if (VN_IS(tempDTypep, QueueDType)) {
                tempElementp
                    = new AstCMethodHard{fl, tempExprp, VCMethod::DYN_AT_WRITE_APPEND, tempRefp};
            }
            tempElementp->dtypep(tempDTypep->subDTypep());
            if (!firstIndexp) {
                firstIndexp = VN_IS(tempElementp, ArraySel) ? VN_AS(tempElementp, ArraySel)->bitp()
                                                            : tempRefp;
            }
            tempDTypep = tempDTypep->virtRefDTypep();
        }

        AstForeachHeader* const headerp
            = new AstForeachHeader{fl, exprp->cloneTree(false), randLoopIndxp};
        AstNodeStmt* randStmtsp = newElementStmtsp(tempElementp);
        if (elemModeVarp) {
            randStmtsp = new AstIf{
                fl,
                new AstLogNot{
                    fl, RandomizeUtil::newElemModeOffp(
                            RandomizeUtil::newMemberRefp(fl, nullptr, elemModeVarp), firstIndexp)},
                randStmtsp};
        }
        // TODO: we should just not clone in 'newRandStmtsp' if not necessary
        if (!tempElementp->backp()) VL_DO_DANGLING(pushDeletep(tempElementp), tempElementp);
        return new AstForeach{fl, headerp, randStmtsp};
    }
    AstNodeStmt* newRandStmtsp(FileLine* fl, AstNodeExpr* exprp, AstVar* randcVarp,
                               AstVar* const outputVarp, int lsb = 0,
                               AstNodeDType* fieldDtp = nullptr) {
        // With fieldDtp, randomize only the packed field of that type at bit lsb of exprp
        if (!fieldDtp) fieldDtp = exprp->dtypep();
        AstNodeDType* const memberDtp = fieldDtp->skipRefp();
        const AstPackArrayDType* const packArrayDtp = VN_CAST(memberDtp, PackArrayDType);
        if (const auto* const structDtp = VN_CAST(memberDtp, StructDType)) {
            AstNodeStmt* stmtsp = nullptr;
            for (AstMemberDType* const smemberp : structDtp->memberspList()) {
                AstNodeStmt* randp = nullptr;
                if (structDtp->packed()) {
                    randp
                        = newRandStmtsp(fl, stmtsp ? exprp->cloneTree(false) : exprp, nullptr,
                                        outputVarp, lsb + smemberp->lsb(), smemberp->subDTypep());
                } else if (smemberp->rand().isRandomizable()) {
                    // IEEE 1800-2023 18.4: an unpacked struct member is only
                    // randomized if its own declaration carries rand/randc.
                    AstStructSel* structSelp
                        = new AstStructSel{fl, exprp->cloneTree(false), smemberp->name()};
                    structSelp->dtypep(smemberp->childDTypep());
                    if (!structSelp->dtypep()) structSelp->dtypep(smemberp->subDTypep());
                    randp = newRandStmtsp(fl, structSelp, nullptr, outputVarp);
                }
                stmtsp = AstNode::addNextNull(stmtsp, randp);
            }
            return stmtsp;
        } else if (const auto* const unionDtp = VN_CAST(memberDtp, UnionDType)) {
            // Illegal for rand/randc, rejected by type upstream for every such
            // case; nothing valid to build a randomize statement for here.
            if (!unionDtp->packed()) return nullptr;
            return newRandStmtsp(fl, exprp, nullptr, outputVarp, lsb,
                                 unionDtp->membersp()->subDTypep());
        } else if (const AstClassRefDType* const classRefDtp = VN_CAST(memberDtp, ClassRefDType)) {
            AstFunc* const memberFuncp
                = m_nullPhase != NullPhase::NONE
                      ? getCreateRandomizeNullFunc(classRefDtp->classp(), m_nullPhase)
                      : V3Randomize::newRandomizeFunc(m_memberMap, classRefDtp->classp());
            AstMethodCall* const callp = new AstMethodCall{fl, exprp, memberFuncp->name()};
            callp->taskp(memberFuncp);
            callp->dtypeFrom(memberFuncp);
            AstAssign* const assignp = new AstAssign{
                fl, new AstVarRef{fl, outputVarp, VAccess::WRITE},
                new AstAnd{fl, new AstVarRef{fl, outputVarp, VAccess::READ}, callp}};
            AstNodeExpr* condp
                = new AstNeq{fl, exprp->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
            // Guard the selected object during ordinary randomize and each null phase.
            if (AstVar* const flagVarp = getRandomizingVarIfCycle(classRefDtp->classp())) {
                condp = new AstLogAnd{
                    fl, condp,
                    new AstNot{fl, new AstMemberSel{fl, exprp->cloneTree(false), flagVarp}}};
            }
            return new AstIf{fl, condp, assignp};
        } else if (memberDtp->isNonPackedArray()) {
            return createArrayForeachLoop(fl, memberDtp, exprp, [&](AstNodeExpr* elemp) {
                return newRandStmtsp(fl, elemp, nullptr, outputVarp);
            });
        } else if (packArrayDtp && packedHasEnum(packArrayDtp)) {
            // A loop over the elements, so each enum gets one of its values
            AstNodeDType* const elemDtp = packArrayDtp->subDTypep();
            AstVar* const idxVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__VpackIdx"),
                             exprp->findUInt32DType()};
            idxVarp->funcLocal(true);
            idxVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            AstSel* const elemp = new AstSel{
                fl, exprp,
                new AstAdd{fl, new AstConst{fl, static_cast<uint32_t>(lsb)},
                           new AstMul{fl, new AstVarRef{fl, idxVarp, VAccess::READ},
                                      new AstConst{fl, static_cast<uint32_t>(elemDtp->width())}}},
                elemDtp->width()};
            elemp->dtypep(elemDtp);
            AstLoop* const loopp = new AstLoop{fl};
            loopp->addStmtsp(new AstLoopTest{
                fl, loopp,
                new AstLt{
                    fl, new AstVarRef{fl, idxVarp, VAccess::READ},
                    new AstConst{fl, static_cast<uint32_t>(packArrayDtp->elementsConst())}}});
            loopp->addStmtsp(newRandStmtsp(fl, elemp, nullptr, outputVarp));
            loopp->addStmtsp(new AstAssign{
                fl, new AstVarRef{fl, idxVarp, VAccess::WRITE},
                new AstAdd{fl, new AstConst{fl, 1}, new AstVarRef{fl, idxVarp, VAccess::READ}}});
            AstNode* const stmtsp = idxVarp;
            stmtsp->addNext(new AstAssign{fl, new AstVarRef{fl, idxVarp, VAccess::WRITE},
                                          new AstConst{fl, 0}});
            stmtsp->addNext(loopp);
            return new AstBegin{fl, "", stmtsp, false};
        } else {
            AstNodeExpr* valp;
            AstNode* randStmtsp = nullptr;  // Draws the random value, before the assignment
            if (AstEnumDType* const enumDtp = VN_CAST(fieldDtp->skipRefToEnump(), EnumDType)) {
                // Random value in a variable: a wide value is copied word by word, each word
                // evaluating the table index again
                AstVar* const randVarp
                    = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__VenumRand"),
                                 exprp->findUInt32DType()};
                randVarp->funcLocal(true);
                randVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                randStmtsp = AstNode::addNext<AstNode, AstNode>(
                    randVarp, new AstAssign{fl, new AstVarRef{fl, randVarp, VAccess::WRITE},
                                            newRandValue(fl, randcVarp, randVarp->dtypep())});
                AstNodeExpr* const moddivp
                    = new AstModDiv{fl, new AstVarRef{fl, randVarp, VAccess::READ},
                                    new AstConst{fl, static_cast<uint32_t>(enumDtp->itemCount())}};
                valp = new AstArraySel{fl, enumValueTabRefp(enumDtp), moddivp};
            } else {
                valp = newRandValue(fl, randcVarp, fieldDtp);
            }
            AstAssign* assignp
                = new AstAssign{fl, new AstSel{fl, exprp, lsb, fieldDtp->width()}, valp};
            AstVar* varp = nullptr;
            exprp->exists([&](const AstVarRef* varrefp) {
                if (varrefp->access().isWriteOrRW()) varp = varrefp->varp();
                return varp != nullptr;
            });
            if (!randStmtsp) return wrapIfRandMode(VN_AS(m_modp, Class), varp, assignp);
            return wrapIfRandMode(VN_AS(m_modp, Class), varp,
                                  new AstBegin{fl, "", randStmtsp->addNext(assignp), false});
        }
    }
    AstNodeExpr* newRandValue(FileLine* const fl, AstVar* const randcVarp,
                              AstNodeDType* const dtypep) {
        if (randcVarp) {
            AstCExpr* const cexprp = new AstCExpr{fl};
            cexprp->add(new AstVarRef{fl, randcVarp, VAccess::READWRITE});
            cexprp->add(".randomize(__Vm_rng)");
            cexprp->dtypep(dtypep);
            return cexprp;
        }

        return new AstRandRNG{
            fl, dtypep->skipRefp()->isFourstate()
                    ? dtypep->findBitDType(dtypep->width(), dtypep->widthMin(), dtypep->numeric())
                    : dtypep};
    }
    // Find pre_randomize/post_randomize task in class hierarchy (walks extendsp chain)
    AstTask* findPrePostTask(AstClass* classp, const string& name) {
        for (AstClass* cp = classp; cp; cp = cp->extendsp() ? cp->extendsp()->classp() : nullptr) {
            if (AstTask* const taskp = VN_CAST(m_memberMap.findMember(cp, name), Task)) {
                return taskp;
            }
        }
        return nullptr;
    }
    void addPrePostCall(AstClass* const classp, AstNodeFTask* const funcp, const string& name) {
        if (AstTask* const userFuncp = findPrePostTask(classp, name)) {
            AstTaskRef* const callp = new AstTaskRef{userFuncp->fileline(), userFuncp};
            funcp->addStmtsp(callp->makeStmt());
        }
    }
    // Per-class virtual wrapper that invokes the class's effective
    // pre_randomize/post_randomize. IEEE 1800-2023 18.6.2: pre_randomize and
    // post_randomize "appear to behave as virtual methods" because randomize()
    // is virtual. The inline `randomize() with` path builds a non-virtual
    // function on the static handle type, so it dispatches pre/post through
    // this wrapper to reach the dynamic type's override.
    AstTask* getCreatePrePostCallback(AstClass* const classp, const string& which) {
        const string name = "__V" + which;
        if (AstTask* const existingp = VN_CAST(m_memberMap.findMember(classp, name), Task)) {
            return existingp;
        }
        AstTask* const taskp = new AstTask{classp->fileline(), name, nullptr};
        taskp->classMethod(true);
        taskp->isVirtual(classp->isExtended());
        classp->addMembersp(taskp);
        m_memberMap.insert(classp, taskp);
        addPrePostCall(classp, taskp, which);
        return taskp;
    }
    // Build the virtual pre/post wrappers across classp's whole hierarchy so a
    // `randomize() with` through a base handle dispatches to a derived
    // override. Returns whether a pre/post wrapper exists anywhere in the
    // hierarchy (cached per static handle type).
    std::pair<bool, bool> buildPrePostVirtualWrappers(AstClass* const classp) {
        const auto cachedIt = m_prePostWrap.find(classp);
        if (cachedIt != m_prePostWrap.end()) return cachedIt->second;
        std::vector<AstClass*> hierp{classp};
        v3Global.rootp()->foreach([&](AstClass* subp) {
            if (subp != classp && AstClass::isClassExtendedFrom(subp, classp))
                hierp.push_back(subp);
        });
        bool hasPre = false;
        bool hasPost = false;
        for (AstClass* const cp : hierp) {
            if (findPrePostTask(cp, "pre_randomize")) {
                getCreatePrePostCallback(cp, "pre_randomize");
                hasPre = true;
            }
            if (findPrePostTask(cp, "post_randomize")) {
                getCreatePrePostCallback(cp, "post_randomize");
                hasPost = true;
            }
        }
        // Ensure the static handle type owns the slot whenever a subclass
        // overrides, so the virtual call resolves on a base handle.
        if (hasPre) getCreatePrePostCallback(classp, "pre_randomize");
        if (hasPost) getCreatePrePostCallback(classp, "post_randomize");
        const std::pair<bool, bool> result{hasPre, hasPost};
        m_prePostWrap.emplace(classp, result);
        return result;
    }
    void addVirtualPrePostCall(AstFunc* const randomizeFuncp, AstClass* const classp,
                               const string& which) {
        FileLine* const fl = classp->fileline();
        AstTask* const wrapperp = getCreatePrePostCallback(classp, which);
        AstClassRefDType* const refDTypep = new AstClassRefDType{fl, classp, nullptr};
        v3Global.rootp()->typeTablep()->addTypesp(refDTypep);
        AstMethodCall* const callp
            = new AstMethodCall{fl, new AstThisRef{fl, refDTypep}, wrapperp->name(), nullptr};
        callp->taskp(wrapperp);
        callp->dtypeSetVoid();
        randomizeFuncp->addStmtsp(callp->makeStmt());
    }
    // Make the statements of 'funcp' after 'lastp' run only if randomize() succeeds
    static void guardPostCallbacks(AstFunc* const funcp, AstNode* const lastp) {
        // IEEE 1800-2023 18.6.3: "If randomize() fails, post_randomize() is not called."
        AstNode* const postp = lastp->nextp();
        if (!postp) return;
        FileLine* const fl = postp->fileline();
        AstVar* const fvarp = VN_AS(funcp->fvarp(), Var);
        funcp->addStmtsp(
            new AstIf{fl, new AstVarRef{fl, fvarp, VAccess::READ}, postp->unlinkFrBackWithNext()});
    }
    // Check if a class (including inherited members) has any rand class-type members
    bool classHasRandClassMembers(AstClass* classp) {
        return classp->existsMember([](const AstClass*, const AstVar* varp) {
            if (!varp->rand().isRandomizable()) return false;
            const AstNodeDType* const dtypep = varp->dtypep()->skipRefp();
            return VN_IS(dtypep, ClassRefDType);
        });
    }
    // True if this class owns a global constraint: a member-select chain rooted
    // at a rand class-typed handle reaching into a sub-object.
    bool classOwnsGlobalConstraint(const AstClass* classp) const {
        return classp->existsMember([](const AstClass*, const AstConstraint* constrp) {
            bool owns = false;
            constrp->foreach([&](const AstMemberSel* memberSelp) {
                const AstNode* const rootp
                    = const_cast<AstMemberSel*>(memberSelp)->baseFromp(true);
                if (const AstVarRef* const refp = VN_CAST(rootp, VarRef)) {
                    // Owns a sub-object constraint if the root is a class handle, or
                    // an array/assoc/queue/unpacked array of class handles.
                    const AstNodeDType* dtypep = refp->varp()->dtypep()->skipRefp();
                    while (const AstNodeDType* const subp = dtypep->subDTypep())
                        dtypep = subp->skipRefp();
                    if (VN_IS(dtypep, ClassRefDType)) owns = true;
                }
            });
            return owns;
        });
    }
    // Get or create __VrandCb_pre/__VrandCb_post task for nested callbacks
    AstTask* getCreateNestedCallbackTask(AstClass* classp, const string& suffix) {
        const string name = "__VrandCb_" + suffix;
        AstTask* taskp = VN_CAST(m_memberMap.findMember(classp, name), Task);
        if (taskp) return taskp;
        taskp = new AstTask{classp->fileline(), name, nullptr};
        taskp->classMethod(true);
        taskp->isVirtual(classp->isExtended());
        classp->addMembersp(taskp);
        m_memberMap.insert(classp, taskp);
        return taskp;
    }
    // Populate nested callback task body: calls pre/post_randomize on globally constrained members
    void populateNestedCallbackTask(AstTask* const callbackTaskp, AstClass* const classp,
                                    const string& cbName) {
        FileLine* const fl = classp->fileline();
        classp->foreachMember([&](AstClass* ownerClassp, AstVar* memberVarp) {
            if (!memberVarp->rand().isRandomizable()) return;
            const AstNodeDType* const dtypep = memberVarp->dtypep()->skipRefp();
            const AstClassRefDType* const classRefp = VN_CAST(dtypep, ClassRefDType);
            if (!classRefp) return;
            AstClass* const memberClassp = classRefp->classp();
            if (memberClassp == classp) return;  // Avoid self-reference
            // Others are randomized by member.randomize(), which calls their callbacks
            if (!memberVarp->globalConstrained() || inRandHandleCycle(memberVarp, classp)) return;

            // Force-visit member class if not yet processed
            if (memberClassp->user1()) {
                iterate(memberClassp);
                m_solverp->startClass(classp);
            }

            AstNode* stmtsp = nullptr;

            // 1. Call member.pre/post_randomize() if exists in hierarchy
            if (AstTask* const userFuncp = findPrePostTask(memberClassp, cbName)) {
                AstMethodCall* const callp = new AstMethodCall{
                    fl, new AstVarRef{fl, ownerClassp, memberVarp, VAccess::WRITE}, cbName};
                callp->taskp(userFuncp);
                callp->dtypeSetVoid();
                stmtsp = AstNode::addNext(stmtsp, callp->makeStmt());
            }

            // 2. Call member.__VrandCb_pre/post() for deeper recursion
            if (classHasRandClassMembers(memberClassp)) {
                const string suffix = (cbName == "pre_randomize") ? "pre" : "post";
                AstTask* const nestedTaskp = getCreateNestedCallbackTask(memberClassp, suffix);
                AstMethodCall* const recurseCallp = new AstMethodCall{
                    fl, new AstVarRef{fl, ownerClassp, memberVarp, VAccess::WRITE},
                    nestedTaskp->name()};
                recurseCallp->taskp(nestedTaskp);
                recurseCallp->dtypeSetVoid();
                stmtsp = AstNode::addNext(stmtsp, recurseCallp->makeStmt());
            }

            if (!stmtsp) return;

            // Wrap in null check
            AstIf* const nullCheckp = new AstIf{
                fl,
                new AstNeq{fl, new AstVarRef{fl, ownerClassp, memberVarp, VAccess::READ},
                           new AstConst{fl, AstConst::Null{}}},
                stmtsp};

            // Wrap in rand_mode check
            callbackTaskp->addStmtsp(wrapIfRandMode(classp, memberVarp, nullCheckp));
        });
    }
    AstVar* getVarFromRef(AstNodeExpr* const exprp) {
        if (AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel)) {
            return memberSelp->varp();
        } else if (AstVarRef* const varrefp = VN_CAST(exprp, VarRef)) {
            return varrefp->varp();
        }
        exprp->v3fatalSrc("Not a MemberSel nor VarRef");
        return nullptr;  // LCOV_EXCL_LINE
    }
    // Build a reference to a rand_mode/constraint_mode dyn-array.
    // Static-mode vars live on the class package; V3Scope resolves the VarRef later.
    AstNodeExpr* makeModeVarRef(AstNodeExpr* const exprp, AstVar* const modeVarp,
                                const VAccess access) {
        if (modeVarp->lifetime().isStatic()) {
            return new AstVarRef{exprp->fileline(), VN_AS(modeVarp->user2p(), NodeModule),
                                 modeVarp, access};
        }
        if (AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel)) {
            AstMemberSel* const newMemberSelp = new AstMemberSel{
                exprp->fileline(), memberSelp->fromp()->cloneTree(false), modeVarp};
            V3LinkLValue::linkLValueSet(newMemberSelp, access);  // Not array indices
            return newMemberSelp;
        }
        UASSERT_OBJ(VN_IS(exprp, VarRef), exprp, "Should be a VarRef");
        return new AstVarRef{exprp->fileline(), VN_AS(modeVarp->user2p(), Class), modeVarp,
                             access};
    }
    AstNodeExpr* getFromp(AstNodeExpr* const exprp) {
        if (AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel)) {
            return memberSelp->fromp();
        } else if (AstMethodCall* const methodCallp = VN_CAST(exprp, MethodCall)) {
            return methodCallp->fromp();
        } else if (AstArraySel* const arraySelp = VN_CAST(exprp, ArraySel)) {
            return arraySelp->fromp();
        }
        return nullptr;
    }
    AstVar* makeTmpRandModeVar(AstNodeExpr* siblingExprp, AstVar* randModeVarp,
                               AstNode*& storeStmtspr, AstNodeStmt*& restoreStmtspr) {
        FileLine* const fl = randModeVarp->fileline();
        AstVar* const randModeTmpVarp = new AstVar{
            fl, VVarType::BLOCKTEMP, m_modeUniqueNames.get(randModeVarp), randModeVarp->dtypep()};
        randModeTmpVarp->funcLocal(m_ftaskp);
        randModeTmpVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        storeStmtspr = AstNode::addNext(
            storeStmtspr,
            new AstAssign{fl, new AstVarRef{fl, randModeTmpVarp, VAccess::WRITE},
                          makeModeVarRef(siblingExprp, randModeVarp, VAccess::READ)});
        storeStmtspr = AstNode::addNext(
            storeStmtspr,
            makeModeSetLoop(fl, makeModeVarRef(siblingExprp, randModeVarp, VAccess::WRITE),
                            new AstConst{fl, 0}, m_ftaskp));
        restoreStmtspr = AstNode::addNext(
            restoreStmtspr,
            new AstAssign{fl, makeModeVarRef(siblingExprp, randModeVarp, VAccess::WRITE),
                          new AstVarRef{fl, randModeTmpVarp, VAccess::READ}});
        return randModeTmpVarp;
    }
    // Returns the common prefix of two hierarchical accesses, or nullptr if there is none
    // e.g. a.b.c and a.b.d -> a.b
    AstNodeExpr* sliceToCommonPrefix(AstNodeExpr* thisp, AstNodeExpr* otherp) {
        static std::vector<AstNodeExpr*> thisHier, otherHier;  // Keep around
                                                               // to avoid reallocations
        thisHier.clear();
        otherHier.clear();
        while (thisp) {
            thisHier.push_back(thisp);
            thisp = getFromp(thisp);
        }
        while (otherp) {
            otherHier.push_back(otherp);
            otherp = getFromp(otherp);
        }
        AstNodeExpr* commonp = nullptr;
        for (auto thisIt = thisHier.rbegin(), otherIt = otherHier.rbegin();
             thisIt != thisHier.rend() && otherIt != otherHier.rend(); ++thisIt, ++otherIt) {
            if ((*thisIt)->type() != (*otherIt)->type()) break;
            if (AstMemberSel* const memberSelp = VN_CAST(*thisIt, MemberSel)) {
                AstMemberSel* const otherMemberSelp = VN_AS(*otherIt, MemberSel);
                if (memberSelp->varp() == otherMemberSelp->varp()) {
                    commonp = memberSelp;
                    continue;
                }
            } else if (AstMethodCall* const thisMethodCallp = VN_CAST(*thisIt, MethodCall)) {
                AstMethodCall* const otherMethodCallp = VN_AS(*otherIt, MethodCall);
                if (thisMethodCallp->taskp() == otherMethodCallp->taskp()) {
                    commonp = thisMethodCallp;
                    continue;
                }
            } else if (AstVarRef* const firstVarRefp = VN_CAST(*thisIt, VarRef)) {
                AstVarRef* const secondVarRefp = VN_AS(*otherIt, VarRef);
                if (firstVarRefp->varp() == secondVarRefp->varp()) {
                    commonp = firstVarRefp;
                    continue;
                }
            } else if (AstArraySel* const thisSelp = VN_CAST(*thisIt, ArraySel)) {
                // Only the copies of the target that V3LinkDot made hold an ArraySel
                UASSERT_OBJ(thisSelp->bitp()->sameTree(VN_AS(*otherIt, ArraySel)->bitp()),
                            thisSelp, "Copies of the randomize() target should match");
                commonp = thisSelp;
                continue;
            }
            break;
        }
        return commonp;
    }

    // Whether an object of classp may reach one of targetp through rand handles
    bool reachesByRandHandle(AstClass* classp, AstClass* targetp,
                             std::set<const AstClass*>& visited) {
        // A handle holds an object of its class or of a class derived from it, so it may
        // hold an object of targetp only if one of the classes derives from the other;
        // classes that just share a base class (e.g. all UVM classes) do not. Visits each
        // once; called per class handle member of a randomized class, which is quadratic
        // only in the number of such classes.
        if (AstClass::isClassExtendedFrom(classp, targetp)
            || AstClass::isClassExtendedFrom(targetp, classp)) {
            return true;
        }
        if (!visited.insert(classp).second) return false;
        for (AstClass* const derivedp : m_derivedClasses[classp]) {
            if (reachesByRandHandle(derivedp, targetp, visited)) return true;
        }
        return classp->existsMember([&](const AstClass*, const AstVar* varp) {
            const AstClassRefDType* const classRefp
                = VN_CAST(RandomizeUtil::arrayElementDTypep(varp->dtypep()), ClassRefDType);
            return varp->rand().isRandomizable() && classRefp
                   && reachesByRandHandle(classRefp->classp(), targetp, visited);
        });
    }

    // Whether rand handle varp of classp, or rand array of handles, is part of a cycle of rand
    // handles
    bool inRandHandleCycle(const AstVar* varp, AstClass* classp) {
        const AstClassRefDType* const classRefp
            = VN_CAST(RandomizeUtil::arrayElementDTypep(varp->dtypep()), ClassRefDType);
        std::set<const AstClass*> visited;
        return varp->rand().isRandomizable() && classRefp
               && reachesByRandHandle(classRefp->classp(), classp, visited);
    }
    // The being-randomized flag of the objects of classp if on a cycle of rand handles
    AstVar* getRandomizingVarIfCycle(AstClass* classp) {
        const bool inCycle = classp->existsMember(
            [&](const AstClass*, const AstVar* varp) { return inRandHandleCycle(varp, classp); });
        return inCycle ? getCreateRandomizingVar(classp) : nullptr;
    }
    // Get or create the flag of an object of classp being randomized
    AstVar* getCreateRandomizingVar(AstClass* classp) {
        // In the base-most class, so the same flag for every class of the object
        classp = classp->baseMostClassp();
        static constexpr const char* const name = "__Vrandomizing";
        if (AstVar* const varp = VN_CAST(m_memberMap.findMember(classp, name), Var)) return varp;
        AstVar* const varp
            = new AstVar{classp->fileline(), VVarType::MEMBER, name, classp->findBitDType()};
        varp->user2p(classp);
        classp->addMembersp(varp);
        m_memberMap.insert(classp, varp);
        return varp;
    }
    // Reference to the being-randomized flag of the object of rand handle varp
    AstMemberSel* newRandomizingSelp(FileLine* fl, AstClass* ownerClassp, AstVar* varp,
                                     const VAccess& access) {
        AstClass* const memberClassp = VN_AS(varp->dtypep()->skipRefp(), ClassRefDType)->classp();
        AstVar* const flagVarp = getCreateRandomizingVar(memberClassp);
        AstMemberSel* const selp
            = new AstMemberSel{fl, new AstVarRef{fl, ownerClassp, varp, VAccess::READ}, flagVarp};
        selp->access(access);
        return selp;
    }
    void addBasicRandomizeBody(AstFunc* const basicRandomizep, AstClass* const nodep,
                               AstVar* randModeVarp) {
        UINFO(9, "addBasicRTB " << nodep);
        FileLine* const fl = nodep->fileline();
        AstVar* const basicFvarp = VN_AS(basicRandomizep->fvarp(), Var);
        AstVarRef* const basicFvarRefp = new AstVarRef{fl, basicFvarp, VAccess::WRITE};
        AstConst* const beginBasicValp = new AstConst{fl, AstConst::WidthedValue{}, 32, 1};
        basicRandomizep->addStmtsp(new AstAssign{fl, basicFvarRefp, beginBasicValp});
        AstNodeFTask* const newp = VN_AS(m_memberMap.findMember(nodep, "new"), NodeFTask);
        UASSERT_OBJ(newp, nodep, "No new() in class");
        nodep->foreachMember([&](AstClass* classp, AstVar* memberVarp) {
            if (!memberVarp->rand().isRandomizable()) return;
            const RandomizeMode randMode = {.asUQuad = memberVarp->user1()};
            if (randMode.usesMode
                && !memberVarp->rand().isRand()) {  // Not randomizable by default
                AstCMethodHard* const setp = new AstCMethodHard{
                    nodep->fileline(),
                    new AstVarRef{fl, VN_AS(randModeVarp->user2p(), NodeModule), randModeVarp,
                                  VAccess::WRITE},
                    VCMethod::ARRAY_AT_WRITE, new AstConst{nodep->fileline(), randMode.index}};
                setp->dtypeSetUInt32();
                newp->addStmtsp(new AstAssign{fl, setp, new AstConst{fl, 0}});
            }
            if (memberVarp->user3()) return;  // Handled in constraints
            const AstNodeDType* const dtypep = memberVarp->dtypep()->skipRefp();
            if (const AstClassRefDType* const classRefp = VN_CAST(dtypep, ClassRefDType)) {
                if (classRefp->classp() == nodep) {
                    memberVarp->v3warn(E_UNSUPPORTED,
                                       "Unsupported: random member variable with the "
                                       "type of the containing class");
                    return;
                }
                // An object reached through a cycle of rand handles may need its own
                // constraints, which global constraints do not clone around the cycle
                const bool inCycle = inRandHandleCycle(memberVarp, nodep);
                const bool basicOnly = memberVarp->globalConstrained() && !inCycle;
                AstFunc* const memberFuncp
                    = basicOnly ? V3Randomize::newRandomizeFunc(m_memberMap, classRefp->classp(),
                                                                BASIC_RANDOMIZE_FUNC_NAME)
                                : V3Randomize::newRandomizeFunc(m_memberMap, classRefp->classp());
                AstMethodCall* const callp
                    = basicOnly ? new AstMethodCall{fl,
                                                    new AstVarRef{fl, classp, memberVarp,
                                                                  VAccess::WRITE},
                                                    BASIC_RANDOMIZE_FUNC_NAME}
                                : new AstMethodCall{
                                      fl, new AstVarRef{fl, classp, memberVarp, VAccess::WRITE},
                                      "randomize"};
                callp->taskp(memberFuncp);
                callp->dtypeFrom(memberFuncp);
                AstVarRef* const basicFvarRefReadp = basicFvarRefp->cloneTree(false);
                basicFvarRefReadp->access(VAccess::READ);
                AstNodeExpr* condp
                    = new AstNeq{fl, new AstVarRef{fl, classp, memberVarp, VAccess::READ},
                                 new AstConst{fl, AstConst::Null{}}};
                // Each object of a cycle is randomized once per call
                if (inCycle) {
                    condp = new AstLogAnd{
                        fl, condp,
                        new AstNot{fl, newRandomizingSelp(fl, classp, memberVarp, VAccess::READ)}};
                }
                AstIf* const assignIfNotNullp
                    = new AstIf{fl, condp,
                                new AstAssign{fl, basicFvarRefp->cloneTree(false),
                                              new AstAnd{fl, basicFvarRefReadp, callp}}};
                basicRandomizep->addStmtsp(wrapIfRandMode(nodep, memberVarp, assignIfNotNullp));
            } else {
                AstVar* const randcVarp = newRandcVarsp(memberVarp, nodep);
                AstVarRef* const refp
                    = new AstVarRef{memberVarp->fileline(), classp, memberVarp, VAccess::WRITE};
                AstVar* const modeVarp = elemModeVarp(memberVarp);
                AstNodeStmt* const stmtp
                    = modeVarp ? createArrayForeachLoop(
                                     fl, memberVarp->dtypep()->skipRefp(), refp,
                                     [&](AstNodeExpr* elemp) {
                                         return newRandStmtsp(fl, elemp, nullptr, basicFvarp);
                                     },
                                     modeVarp)
                               : newRandStmtsp(fl, refp, randcVarp, basicFvarp);
                if (!refp->backp()) VL_DO_DANGLING(refp->deleteTree(), refp);
                AstNodeStmt* blockp
                    = new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), stmtp, false};
                // Elements check the array's rand_mode themselves, unless they are objects
                if (RandomizeUtil::isClassHandleArray(memberVarp))
                    blockp = wrapIfRandMode(nodep, memberVarp, blockp);
                basicRandomizep->addStmtsp(blockp);
            }
        });
    }

    // Creates a lvalue reference to the randomize mode var. Called by visit(AstNodeFTaskRef*)
    AstNodeExpr* makeModeAssignLhs(FileLine* const fl, AstClass* const classp,
                                   AstNodeExpr* const fromp, AstVar* const modeVarp) {
        // For static constraint mode vars, always use VarRef (not MemberSel).
        // At this point V3Class hasn't run yet, so user2p may be nullptr.
        // Generate VarRef with classp as module; V3Scope will update varScopep later
        // when the variable is moved to the class package.
        if (modeVarp->lifetime().isStatic()) {
            // Hint owning class so V3Scope resolves from derived call sites.
            if (fromp) VL_DO_DANGLING(fromp->unlinkFrBack()->deleteTree(), fromp);
            return new AstVarRef{fl, VN_AS(modeVarp->user2p(), NodeModule), modeVarp,
                                 VAccess::WRITE};
        } else if (classp == m_modp) {
            // Called on 'this' or a member of 'this'
            return new AstVarRef{fl, VN_AS(modeVarp->user2p(), NodeModule), modeVarp,
                                 VAccess::WRITE};
        } else {
            AstMemberSel* const memberselp = new AstMemberSel{fl, fromp->unlinkFrBack(), modeVarp};
            memberselp->foreach([](AstVarRef* varrefp) { varrefp->access(VAccess::WRITE); });
            return memberselp;
        }
    }
    // Replace the node with an assignment to the mode variable. Called by visit(AstNodeFTaskRef*)
    void replaceWithModeAssign(AstNodeFTaskRef* const ftaskRefp, AstNode* const receiverp,
                               AstNodeExpr* const lhsp) {
        replaceWithModeAssignAndAppend(ftaskRefp, receiverp, lhsp, nullptr);
    }
    // Append BEFORE swap; backp()/nextp() unreliable after replaceWith.
    void replaceWithModeAssignAndAppend(AstNodeFTaskRef* const ftaskRefp, AstNode* const receiverp,
                                        AstNodeExpr* const lhsp, AstNode* const appendStmtp) {
        FileLine* const fl = ftaskRefp->fileline();
        if (ftaskRefp->argsp()) {
            UASSERT_OBJ(VN_IS(ftaskRefp->backp(), StmtExpr), ftaskRefp, "Should be a statement");
            AstNodeExpr* const rhsp = ftaskRefp->argsp()->exprp()->unlinkFrBack();
            AstNode* newStmtp = nullptr;
            if (receiverp) {
                // Called on a rand member variable/constraint. Set the variable/constraint's
                // mode
                const RandomizeMode rmode = {.asUQuad = receiverp->user1()};
                UASSERT_OBJ(rmode.usesMode, ftaskRefp, "Failed to set usesMode");
                AstCMethodHard* const setp = new AstCMethodHard{fl, lhsp, VCMethod::ARRAY_AT_WRITE,
                                                                new AstConst{fl, rmode.index}};
                setp->dtypeSetUInt32();
                newStmtp = new AstAssign{fl, setp, rhsp};
            } else {
                // For rand_mode: Called on 'this' or a non-rand class instance.
                // For constraint_mode: Called on a class instance.
                // Set the rand mode of all members
                newStmtp = makeModeSetLoop(fl, lhsp, rhsp, m_ftaskp);
            }
            if (appendStmtp) newStmtp->addNext(appendStmtp);
            m_stmtp->replaceWith(newStmtp);
            VL_DO_CLEAR(pushDeletep(m_stmtp), m_stmtp = nullptr);
        } else {
            UASSERT_OBJ(receiverp, ftaskRefp, "Should have receiver");
            UASSERT_OBJ(!appendStmtp, ftaskRefp, "Append path requires arg-form rand_mode");
            const RandomizeMode rmode = {.asUQuad = receiverp->user1()};
            UASSERT_OBJ(rmode.usesMode, ftaskRefp, "Failed to set usesMode");
            AstCMethodHard* const setp = new AstCMethodHard{fl, lhsp, VCMethod::ARRAY_AT_WRITE,
                                                            new AstConst{fl, rmode.index}};
            setp->dtypeSetUInt32();
            ftaskRefp->replaceWith(setp);
            VL_DO_DANGLING(pushDeletep(ftaskRefp), ftaskRefp);
        }
    };

    // Statements clearing the element modes of receiverp, or all arrays of classp if nullptr
    AstNode* newElemModeClearsp(FileLine* const fl, AstNodeExpr* const objp,
                                AstClass* const classp, AstVar* const receiverp) {
        AstNode* stmtsp = nullptr;
        const auto addClear = [&](AstVar* const varp) {
            AstVar* const modeVarp = elemModeVarp(varp);
            if (!modeVarp) return;
            AstNodeExpr* const modesp = RandomizeUtil::newMemberRefp(fl, objp, modeVarp);
            modesp->foreach([](AstVarRef* varrefp) { varrefp->access(VAccess::WRITE); });
            AstCMethodHard* const clearp
                = new AstCMethodHard{fl, modesp, VCMethod::ASSOC_CLEAR, nullptr};
            clearp->dtypeSetVoid();
            stmtsp = AstNode::addNextNull(stmtsp, clearp->makeStmt());
        };
        if (receiverp) {
            addClear(receiverp);
        } else {
            classp->foreachMember([&](AstClass*, AstVar* const varp) { addClear(varp); });
        }
        return stmtsp;
    }
    // Make reference refp, a VarRef or MemberSel, refer to varp instead
    static void retargetMemberRef(AstNodeExpr* const refp, AstVar* const varp) {
        if (AstVarRef* const varrefp = VN_CAST(refp, VarRef)) {
            varrefp->varp(varp);
        } else {
            VN_AS(refp, MemberSel)->varp(varp);
        }
        refp->name(varp->name());
        refp->dtypep(varp->dtypep());
    }
    // Replace an array element's rand_mode() call with an access to the array's element modes
    void replaceWithElemModeAccess(AstNodeFTaskRef* const nodep, AstNodeExpr* const fromp,
                                   AstVar* const arrVarp) {
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* indexp;
        AstNodeExpr* modesp;  // Reached the same way as the array
        if (AstArraySel* const arraySelp = VN_CAST(fromp, ArraySel)) {
            indexp = arraySelp->bitp()->unlinkFrBack();
            modesp = arraySelp->fromp()->unlinkFrBack();
        } else {
            AstCMethodHard* const atp = VN_AS(fromp, CMethodHard);
            indexp = atp->pinsp()->unlinkFrBack();
            modesp = atp->fromp()->unlinkFrBack();
        }
        retargetMemberRef(modesp, elemModeVarp(arrVarp));
        if (nodep->argsp()) {
            UASSERT_OBJ(VN_IS(nodep->backp(), StmtExpr), nodep, "Should be a statement");
            modesp->foreach([](AstVarRef* varrefp) { varrefp->access(VAccess::WRITE); });
            AstNodeExpr* const onp = nodep->argsp()->exprp()->unlinkFrBack();
            AstCMethodHard* const setp
                = new AstCMethodHard{fl, modesp, VCMethod::ARRAY_AT_WRITE, indexp};
            setp->dtypeSetBit();
            AstNodeExpr* const offp
                = new AstEq{fl, onp, new AstConst{fl, AstConst::WidthedValue{}, onp->width(), 0}};
            m_stmtp->replaceWith(new AstAssign{fl, setp, offp});
            VL_DO_CLEAR(pushDeletep(m_stmtp), m_stmtp = nullptr);
            return;
        }
        const RandomizeMode randMode = {.asUQuad = arrVarp->user1()};
        AstNodeExpr* const slotsp = randMode.usesMode ? modesp->cloneTreePure(false) : nullptr;
        AstCMethodHard* const atp = new AstCMethodHard{fl, modesp, VCMethod::ARRAY_AT, indexp};
        atp->dtypeSetUInt32();
        AstNodeExpr* onp = new AstXor{fl, new AstConst{fl, 1}, atp};
        onp->dtypeSetUInt32();
        if (slotsp) {  // Also off while the whole array is
            retargetMemberRef(slotsp, RandModeVars::randModeVarp(VN_AS(arrVarp->user2p(), Class)));
            AstCMethodHard* const slotp = new AstCMethodHard{fl, slotsp, VCMethod::ARRAY_AT,
                                                             new AstConst{fl, randMode.index}};
            slotp->dtypeSetUInt32();
            onp = new AstAnd{fl, slotp, onp};
            onp->dtypeSetUInt32();
        }
        nodep->replaceWith(onp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    // Wrap obj.randomize() with null guard: (obj != null) ? obj.randomize() : 0
    // IEEE 1800 requires randomize() on null handle to return 0.
    // Uses user4() to prevent re-wrapping during iterateChildren.
    void wrapRandomizeCallWithNullGuard(AstNodeFTaskRef* nodep) {
        AstMethodCall* const callp = VN_CAST(nodep, MethodCall);
        if (!callp) return;
        if (callp->user4SetOnce()) return;
        FileLine* const fl = callp->fileline();
        VNRelinker relinker;
        callp->unlinkFrBack(&relinker);
        // The target is used twice, so evaluate one with side effects into a temporary
        AstAssign* assignp = nullptr;
        if (!callp->fromp()->isPure()) {
            AstVar* const varp = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__Vobj"),
                                            callp->fromp()->dtypep()};
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            addTempVarsp(varp);
            assignp = new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                    callp->fromp()->unlinkFrBack()};
            callp->fromp(new AstVarRef{fl, varp, VAccess::READ});
        }
        AstNodeExpr* const checkp
            = new AstNeq{fl, callp->fromp()->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
        AstNodeExpr* newp = new AstCond{fl, checkp, callp, new AstConst{fl, 0}};
        if (assignp) newp = new AstExprStmt{fl, assignp, newp};
        relinker.relink(newp);
    }

    // Handle inline random variable control. After this, the randomize() call has no args
    void handleRandomizeArgs(AstNodeFTaskRef* const nodep) {
        if (!nodep->argsp()) return;
        // Strip the null literal arg. V3Width already rejected mixed/non-null
        // AstConst args.
        bool hasNullArg = false;
        for (AstArg* const argp : nodep->argspList()) {
            if (const AstConst* const constp = VN_CAST(argp->exprp(), Const)) {
                UASSERT_OBJ(constp->num().isNull(), constp,
                            "Non-null AstConst arg to randomize() should have been "
                            "rejected by V3Width");
                hasNullArg = true;
                VL_DO_DANGLING(argp->unlinkFrBack()->deleteTree(), argp);
            }
        }
        // This assumes arguments to always be a member sel from nodep->fromp(), if applicable
        // e.g. LinkDot transformed a.randomize(b, a.c) -> a.randomize(a.b, a.c)
        // Merge pins with common prefixes so that setting their rand mode doesn't interfere
        // with each other.
        // e.g. a.randomize(a.b, a.c, a.b.d) -> a.randomize(a.b, a.c)
        for (AstArg *argp = nodep->argsp(), *nextp = nullptr; argp; argp = nextp) {
            nextp = VN_AS(argp->nextp(), Arg);
            for (AstArg *otherArgp = nextp, *otherNextp = nullptr; otherArgp;
                 otherArgp = otherNextp) {
                otherNextp = VN_AS(otherArgp->nextp(), Arg);
                if (AstNodeExpr* const prefixp
                    = sliceToCommonPrefix(argp->exprp(), otherArgp->exprp())) {
                    if (prefixp == argp->exprp()) {
                        if (nextp == otherArgp) nextp = VN_AS(nextp->nextp(), Arg);
                        VL_DO_DANGLING(otherArgp->unlinkFrBack()->deleteTree(), otherArgp);
                        continue;
                    }
                }
                if (AstNodeExpr* const prefixp
                    = sliceToCommonPrefix(otherArgp->exprp(), argp->exprp())) {
                    if (prefixp == otherArgp->exprp()) {
                        VL_DO_DANGLING(argp->unlinkFrBack()->deleteTree(), argp);
                        break;
                    }
                }
            }
        }
        // Construct temp vars, and store and restore statements
        std::set<AstVar*> savedRandModeVarps;
        AstVar* tmpVarps = nullptr;
        AstNode* storeStmtsp = nullptr;
        AstNode* setStmtsp = nullptr;
        AstNodeStmt* restoreStmtsp = nullptr;
        for (AstArg* const argp : nodep->argspList()) {
            AstNodeExpr* exprp = argp->exprp();
            AstNodeExpr* const commonPrefixp = sliceToCommonPrefix(exprp, nodep);
            UASSERT_OBJ(commonPrefixp != exprp, nodep,
                        "Common prefix should be different than pin");
            FileLine* const fl = argp->fileline();
            while (exprp) {
                if (commonPrefixp == exprp) break;
                AstVar* const randVarp = getVarFromRef(exprp);
                AstClass* const classp = VN_AS(randVarp->user2p(), Class);
                AstVar* const randModeVarp = randVarp->lifetime().isStatic()
                                                 ? getStaticRandModeVar(classp)
                                                 : RandModeVars::randModeVarp(classp);
                UASSERT_OBJ(randModeVarp, randVarp,
                            "Rand var with rand_mode must have a mode array");
                if (savedRandModeVarps.find(randModeVarp) == savedRandModeVarps.end()) {
                    AstVar* const randModeTmpVarp
                        = makeTmpRandModeVar(exprp, randModeVarp, storeStmtsp, restoreStmtsp);
                    savedRandModeVarps.insert(randModeVarp);
                    tmpVarps = AstNode::addNext(tmpVarps, randModeTmpVarp);
                }
                const RandomizeMode randMode = {.asUQuad = randVarp->user1()};
                AstCMethodHard* setp = new AstCMethodHard{
                    fl, makeModeVarRef(exprp, randModeVarp, VAccess::WRITE),
                    VCMethod::ARRAY_AT_WRITE, new AstConst{fl, randMode.index}};
                setp->dtypeSetUInt32();
                setStmtsp
                    = AstNode::addNext(setStmtsp, new AstAssign{fl, setp, new AstConst{fl, 1}});
                exprp = getFromp(exprp);
            }
            VL_DO_DANGLING(argp->unlinkFrBack()->deleteTree(), argp);
        }
        if (hasNullArg) {  // Re-point to the per-class __Vrandomize_null wrapper
            AstClass* targetClassp = nullptr;
            AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall);
            if (methodCallp) {
                const AstNodeDType* const fromDTypep = methodCallp->fromp()->dtypep();
                const AstClassRefDType* const crdtp
                    = VN_CAST(fromDTypep->skipRefp(), ClassRefDType);
                UASSERT_OBJ(crdtp, nodep, "randomize(null) receiver is not a class type");
                targetClassp = crdtp->classp();
            } else {
                targetClassp = VN_CAST(m_modp, Class);
            }
            UASSERT_OBJ(targetClassp, nodep, "randomize(null) target class unresolved");
            AstFunc* const checkOnlyFuncp
                = getCreateRandomizeNullFunc(targetClassp, NullPhase::ENTRY);
            nodep->name(checkOnlyFuncp->name());
            nodep->taskp(checkOnlyFuncp);
            nodep->dtypeFrom(checkOnlyFuncp->dtypep());
        }
        if (tmpVarps) {
            UASSERT_OBJ(storeStmtsp && setStmtsp && restoreStmtsp, nodep, "Should have stmts");
            VNRelinker relinker;
            m_stmtp->unlinkFrBack(&relinker);
            AstNode* const stmtsp = storeStmtsp;
            stmtsp->addNext(setStmtsp);
            stmtsp->addNext(m_stmtp);
            stmtsp->addNext(restoreStmtsp);
            relinker.relink(stmtsp);
            // After relinking, so the function body is complete
            addTempVarsp(tmpVarps);
        }
    }

    // Get or create a randomize(null) method; its body is added by addRandomizeNullBody.
    AstFunc* getCreateRandomizeNullFunc(AstClass* const classp, const NullPhase phase) {
        static constexpr const char* const names[]
            = {"", "__Vrandomize_null", "__Vrandomize_null_pre", "__Vrandomize_null_check",
               "__Vrandomize_null_post"};
        const char* const name = names[static_cast<int>(phase)];
        if (AstFunc* const existingp = VN_AS(m_memberMap.findMember(classp, name), Func)) {
            return existingp;
        }
        AstFunc* const funcp = V3Randomize::newRandomizeFunc(m_memberMap, classp, name);
        m_randomizeNullFuncs.emplace_back(classp, phase, funcp);
        return funcp;
    }
    // Build the body of a randomize(null) method
    void addRandomizeNullBody(AstClass* const classp, const NullPhase phase,
                              AstFunc* const funcp) {
        // Implements IEEE 1800-2023 18.11.1: check all constraints, including those of rand
        // member objects, against the current values without assigning new ones. As for
        // randomize() (18.6.2), pre_randomize() of the object and its active member objects
        // is called first, and post_randomize() last, only if the check succeeds (18.6.3).
        // ENTRY (the randomize(null) call) does PRE, CHECK, then POST if CHECK returned 1;
        // each of these phases also calls the same phase on the member objects.
        FileLine* const fl = classp->fileline();
        AstVar* const fvarp = VN_AS(funcp->fvarp(), Var);
        const auto setResult = [&](AstNodeExpr* const valp) {
            funcp->addStmtsp(new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE}, valp});
        };
        const auto callPhase = [&](NullPhase calledPhase) {
            return new AstFuncRef{fl, getCreateRandomizeNullFunc(classp, calledPhase)};
        };
        if (phase == NullPhase::ENTRY) {  // PRE and POST return 1
            setResult(callPhase(NullPhase::PRE));
            setResult(callPhase(NullPhase::CHECK));
            funcp->addStmtsp(new AstIf{fl, new AstVarRef{fl, fvarp, VAccess::READ},
                                       new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE},
                                                     callPhase(NullPhase::POST)}});
            return;
        }
        // Virtual, so an object of a derived class is checked by its own methods
        for (AstClass* const derivedp : m_derivedClasses[classp])
            getCreateRandomizeNullFunc(derivedp, phase);
        // As for randomize(), an object of a cycle of rand handles is flagged during each
        // phase, so the phase reaches it once
        AstVar* const randomizingVarp = getRandomizingVarIfCycle(classp);
        const auto setRandomizing = [&](bool value) {
            funcp->addStmtsp(
                new AstAssign{fl,
                              new AstVarRef{fl, VN_AS(randomizingVarp->user2p(), NodeModule),
                                            randomizingVarp, VAccess::WRITE},
                              new AstConst{fl, AstConst::BitTrue{}, value}});
        };
        if (randomizingVarp) setRandomizing(true);
        if (phase == NullPhase::PRE) addPrePostCall(classp, funcp, "pre_randomize");
        setResult(phase == NullPhase::CHECK ? m_solverp->lowerCheckOnly(classp, funcp)
                                            : new AstConst{fl, AstConst::WidthedValue{}, 32, 1});
        {
            VL_RESTORER(m_nullPhase);
            m_nullPhase = phase;
            classp->foreachMember([&](AstClass* const ownerClassp, AstVar* const memberVarp) {
                if (!memberVarp->rand().isRandomizable()) return;
                if (!VN_IS(RandomizeUtil::arrayElementDTypep(memberVarp->dtypep()), ClassRefDType))
                    return;
                AstVarRef* const refp = new AstVarRef{fl, ownerClassp, memberVarp, VAccess::READ};
                // The selected leaf's null and cycle flag are checked in newRandStmtsp.
                AstNodeStmt* const stmtp = newRandStmtsp(fl, refp, nullptr, fvarp);
                funcp->addStmtsp(wrapIfRandMode(
                    classp, memberVarp,
                    new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), stmtp, false}));
            });
        }
        if (phase == NullPhase::POST) addPrePostCall(classp, funcp, "post_randomize");
        if (randomizingVarp) setRandomizing(false);
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_randCaseNum);
        VL_RESTORER_COPY(m_randArrayUniqueNames);
        m_modp = nodep;
        m_randCaseNum = 0;
        m_randArrayUniqueNames.reset();
        iterateChildren(nodep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_ftaskp);
        m_ftaskp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstClass* nodep) override {
        m_visitedClasses.insert(nodep);
        // The class lowers the constraints of its base classes with its own, so their
        // array size methods must already be replaced by size variables
        if (nodep->extendsp() && !m_visitedClasses.count(nodep->extendsp()->classp())) {
            iterate(nodep->extendsp()->classp());
        }
        VL_RESTORER(m_modp);
        VL_RESTORER(m_randCaseNum);
        m_modp = nodep;
        m_randCaseNum = 0;
        m_solverp->startClass(nodep);

        iterateChildren(nodep);
        if (!nodep->user1()) return;  // Doesn't need randomize, or already processed
        // Also while being processed, as rand objects of a cycle visit each other
        nodep->user1(false);
        UINFO(9, "Define randomize() for " << nodep);
        nodep->baseMostClassp()->needRNG(true);

        const bool basicFirst = m_globalOwnerClassps.count(nodep);

        FileLine* const fl = nodep->fileline();
        AstFunc* const randomizep = V3Randomize::newRandomizeFunc(m_memberMap, nodep);
        AstVar* const fvarp = VN_AS(randomizep->fvarp(), Var);
        AstVar* const randModeVarp = RandModeVars::randModeVarp(nodep);
        // An object of a cycle of rand handles is flagged while randomized, so it is not
        // randomized again through the cycle
        AstVar* const randomizingVarp = getRandomizingVarIfCycle(nodep);
        if (randomizingVarp) {
            randomizep->addStmtsp(
                new AstAssign{fl,
                              new AstVarRef{fl, VN_AS(randomizingVarp->user2p(), NodeModule),
                                            randomizingVarp, VAccess::WRITE},
                              new AstConst{fl, AstConst::BitTrue{}}});
        }
        addPrePostCall(nodep, randomizep, "pre_randomize");

        // Call nested pre_randomize on rand class-type members (IEEE 18.4.1)
        if (classHasRandClassMembers(nodep)) {
            AstTask* const preTaskp = getCreateNestedCallbackTask(nodep, "pre");
            populateNestedCallbackTask(preTaskp, nodep, "pre_randomize");
            randomizep->addStmtsp((new AstTaskRef{fl, preTaskp})->makeStmt());
        }

        // Both IS_RANDOMIZED and IS_RANDOMIZED_GLOBAL classes need full constraint support
        // IS_RANDOMIZED_GLOBAL classes can be randomized independently
        AstNodeExpr* const beginValp
            = m_solverp->lowerClassRandomize(nodep, randomizep, randModeVarp);

        AstFunc* const basicRandomizep
            = V3Randomize::newRandomizeFunc(m_memberMap, nodep, BASIC_RANDOMIZE_FUNC_NAME);
        addBasicRandomizeBody(basicRandomizep, nodep, randModeVarp);
        AstVarRef* const fvarRefp = new AstVarRef{fl, fvarp, VAccess::WRITE};
        if (m_solverp->basicInClassSolve(nodep)) {
            randomizep->addStmtsp(new AstAssign{fl, fvarRefp, beginValp});
        } else {
            // A basicFirst owner basic-randomizes first, then the solver overrides the
            // constrained leaves, so a globally-constrained leaf (not user3) is still
            // basic-randomized when its type is randomized standalone.
            randomizep->addStmtsp(new AstAssign{
                fl, fvarRefp, basicFirst ? new AstFuncRef{fl, basicRandomizep} : beginValp});

            // Back-end statements after the solver result; emit them after whichever
            // assignment below holds the solver call.
            if (!basicFirst) m_solverp->addAfterClassSolve(nodep, randomizep);

            AstVarRef* const fvarRefReadp = fvarRefp->cloneTree(false);
            fvarRefReadp->access(VAccess::READ);

            // Only after a success, so a failed solve does not randomize rand members, calling
            // their post_randomize
            AstNodeExpr* const secondHalfp
                = basicFirst ? beginValp : new AstFuncRef{fl, basicRandomizep};
            randomizep->addStmtsp(new AstIf{
                fl, fvarRefReadp, new AstAssign{fl, fvarRefp->cloneTree(false), secondHalfp}});

            if (basicFirst) m_solverp->addAfterClassSolve(nodep, randomizep);
        }
        m_solverp->finishClassRandomize(nodep, randomizep, basicRandomizep);

        AstNode* const lastp = randomizep->stmtsp()->lastp();
        // Call nested post_randomize on rand class-type members (IEEE 18.4.1)
        if (classHasRandClassMembers(nodep)) {
            AstTask* const postTaskp = getCreateNestedCallbackTask(nodep, "post");
            populateNestedCallbackTask(postTaskp, nodep, "post_randomize");
            randomizep->addStmtsp((new AstTaskRef{fl, postTaskp})->makeStmt());
        }

        addPrePostCall(nodep, randomizep, "post_randomize");
        guardPostCallbacks(randomizep, lastp);
        if (randomizingVarp) {
            randomizep->addStmtsp(
                new AstAssign{fl,
                              new AstVarRef{fl, VN_AS(randomizingVarp->user2p(), NodeModule),
                                            randomizingVarp, VAccess::WRITE},
                              new AstConst{fl, AstConst::BitFalse{}}});
        }
    }
    void visit(AstRandCase* nodep) override {
        // RANDCASE
        //   CASEITEM expr1 : stmt1
        //   CASEITEM expr2 : stmt2
        // ->
        //   tmp = URandomRange{0, num} + 1   // + 1 so weight 0 means never
        //   if (tmp < expr1) stmt1;
        //   else if (tmp < (expr2 + expr1)) stmt1;
        //   else warning
        // Note this code assumes that the expressions after V3Const are fast to compute
        // Optimize: we would be better with a binary search tree to reduce ifs that execute
        UINFOTREE(9, nodep, "", "rcin:");
        AstNodeDType* const sumDTypep = nodep->findUInt64DType();

        FileLine* const fl = nodep->fileline();
        const std::string name = "__Vrandcase" + cvtToStr(m_randCaseNum++);
        AstVar* const randVarp = new AstVar{fl, VVarType::BLOCKTEMP, name, sumDTypep};
        randVarp->noSubst(true);
        randVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        addTempVarsp(randVarp);
        AstNodeExpr* sump = new AstConst{fl, AstConst::WidthedValue{}, 64, 0};
        AstNodeIf* const firstIfsp
            = new AstIf{fl, new AstConst{fl, AstConst::BitFalse{}}, nullptr, nullptr};
        AstNodeIf* ifsp = firstIfsp;

        for (AstCaseItem* const itemp : nodep->itemspList()) {
            AstNodeExpr* const condp = itemp->condsp()->unlinkFrBack();
            sump
                = new AstAdd{condp->fileline(), sump, new AstExtend{itemp->fileline(), condp, 64}};
            AstNode* const stmtsp
                = itemp->stmtsp() ? itemp->stmtsp()->unlinkFrBackWithNext() : nullptr;
            AstVarRef* const randVarRefp = new AstVarRef{fl, randVarp, VAccess::WRITE};
            AstNodeIf* const newifp
                = new AstIf{itemp->fileline(),
                            new AstLte{condp->fileline(), randVarRefp, sump->cloneTreePure(true)},
                            stmtsp, nullptr};
            ifsp->addElsesp(newifp);
            ifsp = newifp;
        }
        AstDisplay* const dispp = new AstDisplay{
            fl, VDisplayType::DT_ERROR, "All randcase items had 0 weights (IEEE 1800-2023 18.16)",
            nullptr, nullptr};
        UASSERT_OBJ(m_modp, nodep, "randcase not under module");
        dispp->fmtp()->timeunit(m_modp->timeunit());
        ifsp->addElsesp(dispp);

        AstNodeExpr* const randp = new AstRand{fl, nullptr, false};
        randp->dtypeSetUInt64();
        AstVarRef* const randVarRefp = new AstVarRef{fl, randVarp, VAccess::WRITE};
        AstNode* const newp
            = new AstAssign{fl, randVarRefp,
                            new AstAdd{fl, new AstConst{fl, AstConst::Unsized64{}, 1},
                                       new AstModDiv{fl, randp, sump}}};
        newp->addNext(firstIfsp);
        if (debug() >= 9) newp->dumpTreeAndNext(cout, "-  rcnew: ");
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (nodep->name() == "rand_mode") {
            AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall);
            AstNodeExpr* const fromp = methodCallp ? methodCallp->fromp() : nullptr;
            if (AstVar* const arrVarp = randModeElemArrayp(fromp)) {
                UASSERT_OBJ(m_elemModes.hasModes(arrVarp), nodep,
                            "Invalid element rand_mode() should have been removed");
                replaceWithElemModeAccess(nodep, fromp, arrVarp);
                return;
            }
            const RandModeTarget randModeTarget = RandModeTarget::get(fromp, m_modp);
            UASSERT_OBJ(randModeTarget.classp, nodep,
                        "Should have checked in RandomizeMarkVisitor");
            AstVar* const receiverp = randModeTarget.receiverp;
            const bool isClassLevel = !(receiverp && receiverp->rand().isRand());
            // Class-level rand_mode(N) must also flush the shared static array.
            AstNode* classLevelStaticLoopp = nullptr;
            if (isClassLevel && nodep->argsp()) {
                if (AstVar* const sVarp = getStaticRandModeVar(randModeTarget.classp)) {
                    FileLine* const fl = nodep->fileline();
                    AstNodeExpr* const staticLhsp
                        = makeModeAssignLhs(fl, randModeTarget.classp, nullptr, sVarp);
                    AstNodeExpr* const argClonep = nodep->argsp()->exprp()->cloneTreePure(false);
                    classLevelStaticLoopp = makeModeSetLoop(fl, staticLhsp, argClonep, m_ftaskp);
                }
            }
            const bool receiverIsStaticRand
                = receiverp && receiverp->rand().isRand() && receiverp->lifetime().isStatic();
            AstVar* const randModeVarp = receiverIsStaticRand
                                             ? getStaticRandModeVar(randModeTarget.classp)
                                             : RandModeVars::randModeVarp(randModeTarget.classp);
            if (!randModeVarp) {
                UASSERT_OBJ(isClassLevel && classLevelStaticLoopp, nodep,
                            "Per-instance rand_mode var missing without static fallback");
                UASSERT_OBJ(VN_IS(nodep->backp(), StmtExpr), nodep, "Should be a statement");
                m_stmtp->replaceWith(classLevelStaticLoopp);
                VL_DO_CLEAR(pushDeletep(m_stmtp), m_stmtp = nullptr);
                return;
            }
            // Without an index, rand_mode(N) of an array sets all its elements
            // (IEEE 1800-2023 18.8), so drop their own modes
            AstNode* const clearsp
                = nodep->argsp() ? newElemModeClearsp(nodep->fileline(), randModeTarget.fromp,
                                                      randModeTarget.classp,
                                                      isClassLevel ? nullptr : receiverp)
                                 : nullptr;
            AstNodeExpr* const lhsp = makeModeAssignLhs(nodep->fileline(), randModeTarget.classp,
                                                        randModeTarget.fromp, randModeVarp);
            replaceWithModeAssignAndAppend(
                nodep, receiverp && receiverp->rand().isRand() ? receiverp : nullptr, lhsp,
                AstNode::addNextNull(classLevelStaticLoopp, clearsp));
            return;
        }

        if (nodep->name() == "constraint_mode") {
            AstMethodCall* const methodCallp = VN_CAST(nodep, MethodCall);
            AstNodeExpr* fromp = methodCallp ? methodCallp->fromp() : nullptr;
            AstConstraint* constrp = nullptr;
            AstClass* classp = VN_CAST(m_modp, Class);
            if (AstConstraintRef* const constrRefp = VN_CAST(fromp, ConstraintRef)) {
                constrp = constrRefp->constrp();
                if (constrRefp->fromp()) {
                    fromp = constrRefp->fromp();
                    classp = VN_AS(fromp->dtypep()->skipRefp(), ClassRefDType)->classp();
                }
            } else if (fromp) {
                classp = VN_AS(fromp->dtypep()->skipRefp(), ClassRefDType)->classp();
            }
            UASSERT_OBJ(classp, nodep, "Failed to find class");
            // Use correct mode variable based on whether constraint is static
            AstVar* const constraintModeVarp = (constrp && constrp->isStatic())
                                                   ? getStaticConstraintModeVar(classp)
                                                   : getConstraintModeVar(classp);
            AstNodeExpr* const lhsp
                = makeModeAssignLhs(nodep->fileline(), classp, fromp, constraintModeVarp);
            replaceWithModeAssign(nodep, constrp, lhsp);
            return;
        }

        if (nodep->name() != "randomize") {
            // Iterate children so nested rand_mode/constraint_mode/randomize calls
            // inside function arguments are still visited and transformed
            iterateChildren(nodep);
            return;
        }

        if (nodep->classOrPackagep() && nodep->classOrPackagep()->name() == "std") {
            // Handle std::randomize; create wrapper function that calls basicStdRandomization on
            // each varref argument, then transform nodep to call that wrapper
            const bool inStaticContext = m_ftaskp && m_ftaskp->isStatic();
            AstVar* const stdrandp = createStdRandomGenerator(m_modp);
            AstFunc* const randomizeFuncp
                = V3Randomize::newRandomizeStdFunc(m_modp, m_inlineUniqueStdName.get(nodep));
            // When called from a static function, mark helper and stdrand as static
            // so V3Class moves them to __Vclpkg alongside the calling function
            if (inStaticContext) {
                stdrandp->lifetime(VLifetime::STATIC_EXPLICIT);
                randomizeFuncp->isStatic(true);
            }
            randomizeFuncp->addStmtsp(
                new AstAssign{nodep->fileline(),
                              new AstVarRef{nodep->fileline(), VN_AS(randomizeFuncp->fvarp(), Var),
                                            VAccess::WRITE},
                              new AstConst{nodep->fileline(), AstConst::WidthedValue{}, 32, 1}});
            std::unique_ptr<CaptureVisitor> withCapturep;
            int argn = 0;
            AstWith* const withp = nodep->withp();
            // IEEE 1800-2023 18.6.3: "If randomize() fails, the constraints are infeasible, and
            // the random variables retain their previous values." Save every argument before
            // any basic randomization, and restore them if the solver fails.
            AstNode* restoreStmtsp = nullptr;
            AstNode* basicStmtsp = nullptr;
            for (const AstArg* const argp : nodep->argspList()) {
                AstNodeExpr* const exprp = argp->exprp();
                AstVar* const refvarp
                    = new AstVar{exprp->fileline(), VVarType::MEMBER,
                                 "__Varg"s + std::to_string(++argn), exprp->dtypep()};
                refvarp->setStdRandomizeArg();
                // Replace argument occurrences in 'with' clause with __Varg* reference.
                if (withp) {
                    withp->foreach([&](AstNodeExpr* exp) {
                        if (sameSelection(exp, exprp)) {
                            AstVarRef* const replaceVarp
                                = new AstVarRef{exprp->fileline(), refvarp, VAccess::READWRITE};
                            exp->replaceWith(replaceVarp);
                            replaceVarp->user1(exp->user1());
                            replaceVarp->varp()->user2p(m_modp);
                            VL_DO_DANGLING(pushDeletep(exp), exp);
                        }
                    });
                }
                refvarp->direction(VDirection::REF);
                refvarp->funcLocal(true);
                refvarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                randomizeFuncp->addStmtsp(refvarp);
                if (withp) {
                    FileLine* const fl = exprp->fileline();
                    AstVar* const prevVarp
                        = new AstVar{fl, VVarType::BLOCKTEMP, "__Vprev"s + std::to_string(argn),
                                     exprp->dtypep()};
                    prevVarp->funcLocal(true);
                    prevVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                    randomizeFuncp->addStmtsp(prevVarp);
                    randomizeFuncp->addStmtsp(
                        new AstAssign{fl, new AstVarRef{fl, prevVarp, VAccess::WRITE},
                                      new AstVarRef{fl, refvarp, VAccess::READ}});
                    restoreStmtsp = AstNode::addNextNull<AstNode, AstNode>(
                        restoreStmtsp,
                        new AstAssign{fl, new AstVarRef{fl, refvarp, VAccess::WRITE},
                                      new AstVarRef{fl, prevVarp, VAccess::READ}});
                }

                basicStmtsp = AstNode::addNextNull<AstNode, AstNode>(
                    basicStmtsp,
                    newBasicStdRandStmtsp(
                        nodep->fileline(), stdrandp, VN_AS(randomizeFuncp->fvarp(), Var),
                        new AstVarRef{exprp->fileline(), refvarp, VAccess::READWRITE}));
            }
            if (basicStmtsp) randomizeFuncp->addStmtsp(basicStmtsp);
            if (withp) {
                FileLine* const fl = nodep->fileline();
                withCapturep = std::make_unique<CaptureVisitor>(withp->exprp(), m_modp, nullptr);
                withCapturep->addFunctionArguments(randomizeFuncp);
                AstNodeExpr* const solverCallp = m_solverp->lowerStdRandomizeWith(
                    nodep, randomizeFuncp, withp->exprp()->unlinkFrBackWithNext(), stdrandp);
                AstVar* const fvarp = VN_AS(randomizeFuncp->fvarp(), Var);
                AstNodeExpr* const andExprp
                    = new AstAnd{fl, new AstVarRef{fl, fvarp, VAccess::READ}, solverCallp};
                randomizeFuncp->addStmtsp(
                    new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE}, andExprp});
                m_solverp->finishStdRandomizeWith(randomizeFuncp, stdrandp);
                if (restoreStmtsp) {
                    randomizeFuncp->addStmtsp(
                        new AstIf{fl, new AstLogNot{fl, new AstVarRef{fl, fvarp, VAccess::READ}},
                                  restoreStmtsp});
                }
                // Remove With nodes as processed
                VL_DO_DANGLING(withp->unlinkFrBack()->deleteTree(), withp);
            }
            // Replace the node with a call to that function
            nodep->name(randomizeFuncp->name());
            nodep->taskp(randomizeFuncp);
            nodep->dtypeFrom(randomizeFuncp->dtypep());
            if (VN_IS(m_modp, Class)) nodep->classOrPackagep(m_modp);
            if (withCapturep) nodep->addArgsp(withCapturep->getArgs());
            UINFOTREE(9, nodep, "", "std::rnd-call");
            UINFOTREE(9, randomizeFuncp, "", "std::rnd-func");
            return;
        }
        handleRandomizeArgs(nodep);

        AstWith* const withp = nodep->withp();
        if (!withp) {
            iterateChildren(nodep);
            wrapRandomizeCallWithNullGuard(nodep);
            return;
        }
        withp->unlinkFrBack();
        iterateChildren(nodep);

        AstClass* classp = nullptr;
        if (AstMethodCall* const callp = VN_CAST(nodep, MethodCall)) {
            const AstNodeDType* const fromDTypep = callp->fromp()->dtypep();
            UASSERT_OBJ(fromDTypep, callp->fromp(), "Object dtype is not linked");
            const AstClassRefDType* const classrefdtypep
                = VN_CAST(fromDTypep->skipRefp(), ClassRefDType);
            UASSERT_OBJ(classrefdtypep, callp->fromp(),
                        "Randomize called on expression of non-class type "
                            << fromDTypep->skipRefp()->prettyDTypeNameQ()
                            << " (it should be detected earlier)");
            classp = classrefdtypep->classp();
            UASSERT_OBJ(classp, classrefdtypep, "Class type is unlinked to its ref type");
        } else {
            classp = VN_CAST(m_modp, Class);
            UASSERT_OBJ(classp, m_modp, "Module not class, should have failed in V3Width");
        }
        if (classp->user1()) {
            // We need to first ensure that the class constraints are transformed
            // NOTE: This is safe only because AstClass visit function overwrites all
            // nesting-dependent state variables
            iterate(classp);
        }

        m_solverp->prepareInlineRandomize(classp,
                                          [this](AstClass* const relatedp) { iterate(relatedp); });

        AstFunc* const randomizeFuncp = V3Randomize::newRandomizeFunc(
            m_memberMap, classp, m_inlineUniqueNames.get(nodep), false);
        // As for randomize()
        AstVar* const randomizingVarp = getRandomizingVarIfCycle(classp);
        if (randomizingVarp) {
            randomizeFuncp->addStmtsp(new AstAssign{
                nodep->fileline(),
                new AstVarRef{nodep->fileline(), VN_AS(randomizingVarp->user2p(), NodeModule),
                              randomizingVarp, VAccess::WRITE},
                new AstConst{nodep->fileline(), AstConst::BitTrue{}}});
        }

        // A base-handle `randomize() with` must still reach a derived
        // pre/post_randomize. Route them through per-class virtual wrappers
        // when the static handle type participates in inheritance.
        const std::pair<bool, bool> prePostWrap = classp->isExtended()
                                                      ? buildPrePostVirtualWrappers(classp)
                                                      : std::pair<bool, bool>{false, false};
        if (prePostWrap.first) {
            addVirtualPrePostCall(randomizeFuncp, classp, "pre_randomize");
        } else {
            addPrePostCall(classp, randomizeFuncp, "pre_randomize");
        }

        // Call nested pre_randomize on rand class-type members (IEEE 18.4.1)
        if (classHasRandClassMembers(classp)) {
            AstTask* const preTaskp = getCreateNestedCallbackTask(classp, "pre");
            if (!preTaskp->stmtsp()) {
                populateNestedCallbackTask(preTaskp, classp, "pre_randomize");
            }
            randomizeFuncp->addStmtsp((new AstTaskRef{nodep->fileline(), preTaskp})->makeStmt());
        }

        // Detach the expression and prepare variable copies
        const CaptureVisitor captured{withp->exprp(), m_modp, classp, !VN_IS(nodep, MethodCall)};
        // Add function arguments
        captured.addFunctionArguments(randomizeFuncp);

        AstFunc* const basicRandomizeFuncp
            = V3Randomize::newRandomizeFunc(m_memberMap, classp, BASIC_RANDOMIZE_FUNC_NAME);
        AstFuncRef* const basicRandomizeFuncCallp
            = new AstFuncRef{nodep->fileline(), basicRandomizeFuncp};

        // Constraint setup and solver calls, which also set the return value
        m_solverp->lowerInlineRandomize(nodep, classp, randomizeFuncp,
                                        withp->exprp()->unlinkFrBackWithNext(),
                                        captured.getThisp(), basicRandomizeFuncCallp);

        AstNode* const lastp = randomizeFuncp->stmtsp()->lastp();
        // Call nested post_randomize on rand class-type members (IEEE 18.4.1)
        if (classHasRandClassMembers(classp)) {
            AstTask* const postTaskp = getCreateNestedCallbackTask(classp, "post");
            if (!postTaskp->stmtsp()) {
                populateNestedCallbackTask(postTaskp, classp, "post_randomize");
            }
            randomizeFuncp->addStmtsp((new AstTaskRef{nodep->fileline(), postTaskp})->makeStmt());
        }

        if (prePostWrap.second) {
            addVirtualPrePostCall(randomizeFuncp, classp, "post_randomize");
        } else {
            addPrePostCall(classp, randomizeFuncp, "post_randomize");
        }
        guardPostCallbacks(randomizeFuncp, lastp);
        if (randomizingVarp) {
            randomizeFuncp->addStmtsp(new AstAssign{
                nodep->fileline(),
                new AstVarRef{nodep->fileline(), VN_AS(randomizingVarp->user2p(), NodeModule),
                              randomizingVarp, VAccess::WRITE},
                new AstConst{nodep->fileline(), AstConst::BitFalse{}}});
        }

        // Replace the node with a call to that function
        nodep->name(randomizeFuncp->name());
        nodep->addArgsp(captured.getArgs());
        nodep->taskp(randomizeFuncp);
        nodep->dtypeFrom(randomizeFuncp->dtypep());
        nodep->classOrPackagep(classp);
        UINFO(9, "Added `%s` randomization procedure");
        wrapRandomizeCallWithNullGuard(nodep);
        VL_DO_DANGLING(withp->deleteTree(), withp);
    }
    void visit(AstConstraint* nodep) override {
        VL_RESTORER(m_constraintp);
        m_constraintp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstCMethodHard* nodep) override {
        iterateChildren(nodep);
        if (m_constraintp) m_solverp->lowerConstraintMethod(m_modp, m_constraintp, nodep);
    }
    void visit(AstNodeStmt* nodep) override {
        VL_RESTORER(m_stmtp);
        m_stmtp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    RandomizeVisitor(AstNetlist* nodep, const ClonedConstraints& cloneObjps,
                     const std::unordered_set<AstVar*>& elemModeArrays)
        : m_inlineUniqueNames{"__Vrandwith"}
        , m_elemModes{elemModeArrays}
        , m_solverp{v3Global.solverBackendp()->newLowering(m_memberMap, m_uniqueNames, m_modeVars,
                                                           m_elemModes, cloneObjps, deleter())} {
        nodep->foreach([&](AstClass* const classp) {
            if (classp->extendsp())
                m_derivedClasses[classp->extendsp()->classp()].push_back(classp);
        });
        createRandomizeClassVars(nodep);
        // Flag local constraint leaves as solver-owned so __VBasicRand skips them.
        // Runs before any class is lowered. Only a randomized class counts, and
        // only a leaf owned by the constraint's own class: a leaf reached through
        // a global constraint stays basic-randomized so a standalone randomize()
        // of its type still randomizes it (issue #7833); a class-typed sub-object
        // is skipped so its own members are still basic-randomized.
        nodep->foreach([&](AstClass* const classp) {
            if (!classp->user1()) return;
            // Before any class unlinks the member-selects of the constraints it shares
            if (classOwnsGlobalConstraint(classp)) m_globalOwnerClassps.insert(classp);
            classp->foreachMember([&](AstClass* const ownerClassp, AstConstraint* const constrp) {
                constrp->foreach([&](AstMemberSel* const memberSelp) {
                    AstVar* const varp = memberSelp->varp();
                    if (VN_IS(varp->dtypep()->skipRefp(), ClassRefDType)) return;
                    if (VN_AS(varp->user2p(), NodeModule) != ownerClassp) return;
                    if (!varp->user3()) varp->user3(true);
                });
            });
        });

        iterate(nodep);
        // Grows while the methods of member objects and derived classes are created
        for (size_t i = 0; i < m_randomizeNullFuncs.size(); ++i) {
            addRandomizeNullBody(std::get<0>(m_randomizeNullFuncs[i]),
                                 std::get<1>(m_randomizeNullFuncs[i]),
                                 std::get<2>(m_randomizeNullFuncs[i]));
        }
        nodep->foreach([&](AstConstraint* constrp) {
            VL_DO_DANGLING(pushDeletep(constrp->unlinkFrBack()), constrp);
        });
    }
    ~RandomizeVisitor() override = default;
};

//######################################################################
// Randomize method class functions

// SMT application of op to one or more terms, a single term standing alone
static std::string smtJoin(const char* op, const std::vector<std::string>& terms) {
    // SMT-LIB 2.6 'and'/'or' take at least two arguments
    if (terms.size() == 1) return terms[0];
    std::string result = std::string{"("} + op;
    for (const std::string& term : terms) result += " " + term;
    return result + ")";
}

// SMT Bool term restricting packed valueExpr to its enum values, empty if it holds no enum
static std::string enumDomainTerm(const AstNodeDType* dtypep, const std::string& valueExpr) {
    dtypep = dtypep->skipRefToEnump();
    std::vector<std::string> terms;
    if (const AstEnumDType* const enumDtp = VN_CAST(dtypep, EnumDType)) {
        for (const AstEnumItem* const itemp : enumDtp->itemspList()) {
            const V3Number& num = VN_AS(itemp->valuep(), Const)->num();
            if (num.isFourState()) continue;  // The solver can't produce X/Z
            terms.push_back("(= " + valueExpr + " (_ bv" + num.toDecimalU() + " "
                            + cvtToStr(enumDtp->width()) + "))");
        }
        return terms.empty() ? "false" : smtJoin("or", terms);
    }
    // Enums inside packed arrays constrain their bit slice; not enum members of a packed
    // struct or union (IEEE 1800-2023 18.4)
    if (const AstPackArrayDType* const arrayDtp = VN_CAST(dtypep, PackArrayDType)) {
        const AstNodeDType* const elemDtp = arrayDtp->subDTypep();
        const int width = elemDtp->width();
        for (int i = 0; i < arrayDtp->elementsConst(); ++i) {
            const std::string term
                = enumDomainTerm(elemDtp, "((_ extract " + cvtToStr(i * width + width - 1) + " "
                                              + cvtToStr(i * width) + ") " + valueExpr + ")");
            if (term.empty()) break;  // No element holds an enum
            terms.push_back(term);
        }
    }
    return terms.empty() ? "" : smtJoin("and", terms);
}

std::string V3Randomize::enumDomain(AstNodeDType* dtypep) {
    return enumDomainTerm(RandomizeUtil::arrayElementDTypep(dtypep), "__Ve");
}

// Restrict each solver variable holding enums, or an array of such, to the enum's values
static void addEnumDomains(AstNetlist* nodep) {
    // At each registration, after lowering, so registrations made or copied anywhere are
    // covered: members reached through handles, elements of arrays, fields of object-array
    // elements (IEEE 1800-2023 18.4). Enum fields of unpacked structs are registered, with
    // their domain, by the runtime from the struct's memberEnumDomains().
    std::vector<AstCMethodHard*> writeVarps;
    nodep->foreach([&](AstCMethodHard* const methodp) {
        if (methodp->method() == VCMethod::RANDOMIZER_WRITE_VAR) writeVarps.push_back(methodp);
    });
    for (AstCMethodHard* const writeVarp : writeVarps) {
        const std::string domain = V3Randomize::enumDomain(writeVarp->pinsp()->dtypep());
        if (domain.empty()) continue;
        FileLine* const fl = writeVarp->fileline();
        AstNode* const namep = writeVarp->pinsp()->nextp()->nextp();  // After variable, width
        AstCMethodHard* const domainp = new AstCMethodHard{
            fl, writeVarp->fromp()->cloneTreePure(false), VCMethod::RANDOMIZER_ENUM_DOMAIN,
            VN_AS(namep, NodeExpr)->cloneTreePure(false)};
        domainp->addPinsp(new AstCExpr{fl, AstCExpr::Pure{}, "\"" + domain + "\""});
        domainp->dtypeSetVoid();
        VN_AS(writeVarp->backp(), StmtExpr)->addNextHere(domainp->makeStmt());
    }
}

void V3Randomize::randomizeNetlist(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    {
        // Keyed by constraints, which are not deleted until RandomizeVisitor's end
        ClonedConstraints cloneObjps;
        std::unordered_set<AstVar*> elemModeArrays;
        const RandomizeMarkVisitor markVisitor{nodep, cloneObjps, elemModeArrays};
        const RandomizeVisitor randomizeVisitor{nodep, cloneObjps, elemModeArrays};
        for (const auto& it : cloneObjps) it.second.objp->deleteTree();
    }
    addEnumDomains(nodep);
    V3Global::dumpCheckGlobalTree("randomize", 0, dumpTreeEitherLevel() >= 3);
}

AstFunc* V3Randomize::newRandomizeFunc(VMemberMap& memberMap, AstClass* nodep,
                                       const std::string& name, bool allowVirtual,
                                       bool childDType) {
    AstFunc* funcp = VN_AS(memberMap.findMember(nodep, name), Func);
    if (!funcp) {
        v3Global.useRandomizeMethods(true);
        AstNodeDType* const dtypep
            = childDType
                  ? new AstBasicDType{nodep->fileline(), VBasicDTypeKwd::INT}
                  : nodep->findBitDType(32, 32, VSigning::SIGNED);  // IEEE says int return of 0/1
        AstVar* const fvarp = childDType
                                  ? new AstVar{nodep->fileline(), VVarType::MEMBER, name,
                                               VFlagChildDType{}, dtypep}
                                  : new AstVar{nodep->fileline(), VVarType::MEMBER, name, dtypep};
        fvarp->fileline()->warnOff(V3ErrorCode::NORETURN, true);
        fvarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        fvarp->funcLocal(true);
        fvarp->funcReturn(true);
        fvarp->direction(VDirection::OUTPUT);
        nodep->addMembersp(funcp);
        funcp = new AstFunc{nodep->fileline(), name, nullptr, fvarp};
        if (!childDType) funcp->dtypep(dtypep);
        funcp->classMethod(true);
        funcp->isVirtual(allowVirtual && nodep->isExtended());
        nodep->addMembersp(funcp);
        memberMap.insert(nodep, funcp);
    }
    return funcp;
}

AstFunc* V3Randomize::newRandomizeStdFunc(AstNodeModule* nodep, const std::string& name) {
    AstFunc* funcp = nullptr;
    v3Global.useRandomizeMethods(true);
    AstNodeDType* const dtypep = nodep->findBitDType(32, 32, VSigning::SIGNED);
    AstVar* const fvarp = new AstVar{nodep->fileline(), VVarType::MEMBER, name, dtypep};
    fvarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
    fvarp->funcLocal(true);
    fvarp->funcReturn(true);
    fvarp->direction(VDirection::OUTPUT);
    funcp = new AstFunc{nodep->fileline(), name, nullptr, fvarp};
    funcp->dtypep(dtypep);
    if (VN_IS(nodep, Class)) {
        funcp->classMethod(true);
    } else {
        funcp->classMethod(true);
        funcp->isStatic(true);
    }
    nodep->addStmtsp(funcp);
    return funcp;
}

AstFunc* V3Randomize::newSRandomFunc(VMemberMap& memberMap, AstClass* nodep) {
    AstClass* const basep = nodep->baseMostClassp();
    AstFunc* funcp = VN_AS(memberMap.findMember(basep, "srandom"), Func);
    if (!funcp) {
        v3Global.useRandomizeMethods(true);
        AstNodeDType* const dtypep
            = basep->findBitDType(32, 32, VSigning::SIGNED);  // IEEE says argument 0/1
        AstVar* const ivarp = new AstVar{basep->fileline(), VVarType::MEMBER, "seed", dtypep};
        ivarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        ivarp->funcLocal(true);
        ivarp->direction(VDirection::INPUT);
        funcp = new AstFunc{basep->fileline(), "srandom", ivarp, nullptr};
        funcp->dtypep(basep->findVoidDType());
        funcp->classMethod(true);
        funcp->isVirtual(false);
        basep->addMembersp(funcp);
        memberMap.insert(nodep, funcp);
        // For std::process, seed the per-process RNG via m_process->srandom()
        // For regular classes, seed the per-object RNG via __Vm_rng
        AstCStmt* const cstmtp = new AstCStmt{basep->fileline()};
        if (basep->name() == "process") {
            cstmtp->add("m_process->srandom(");
        } else {
            cstmtp->add("__Vm_rng.srandom(");
            basep->needRNG(true);
        }
        cstmtp->add(new AstVarRef{basep->fileline(), ivarp, VAccess::READ});
        cstmtp->add(");");
        funcp->addStmtsp(cstmtp);
    }
    return funcp;
}

bool V3Randomize::isRandomizeTarget(const AstNodeExpr* exprp, const AstNodeExpr* fromp) {
    // V3LinkDot copied the target into each argument, which is an lvalue, so a
    // sameTree() would fail on the access. Compare the selected objects instead.
    while (exprp->type() == fromp->type()) {
        if (const AstVarRef* const refp = VN_CAST(exprp, VarRef)) {
            return refp->varp() == VN_AS(fromp, VarRef)->varp();
        } else if (const AstMemberSel* const selp = VN_CAST(exprp, MemberSel)) {
            const AstMemberSel* const fromSelp = VN_AS(fromp, MemberSel);
            if (selp->varp() != fromSelp->varp()) return false;
            exprp = selp->fromp();
            fromp = fromSelp->fromp();
        } else if (const AstArraySel* const selp = VN_CAST(exprp, ArraySel)) {
            const AstArraySel* const fromSelp = VN_AS(fromp, ArraySel);
            if (!selp->bitp()->sameTree(fromSelp->bitp())) return false;
            exprp = selp->fromp();
            fromp = fromSelp->fromp();
        } else {
            return false;
        }
    }
    return false;
}
