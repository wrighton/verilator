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
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "verilatedos.h"

#include "V3Randomize.h"

#include "V3Ast.h"
#include "V3Const.h"
#include "V3ConstPool.h"
#include "V3Container.h"
#include "V3Error.h"
#include "V3FileLine.h"
#include "V3Global.h"
#include "V3LinkLValue.h"
#include "V3MemberMap.h"
#include "V3Task.h"
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
// Constants for global constraint processing

static constexpr const char* GLOBAL_CONSTRAINT_SEPARATOR = "__DT__";
static constexpr const char* BASIC_RANDOMIZE_FUNC_NAME = "__VBasicRand";

// Walk extends chain to find __Vrandmode variable (stored in AstClass::user2p).
// user2p is only set on the root class where __Vrandmode was created, so
// derived classes need this chain walk. Accepts AstNodeModule* for flexibility.
static AstVar* getRandModeVarFromClass(AstNodeModule* classp) {
    while (classp) {
        if (classp->user2p()) return VN_AS(classp->user2p(), Var);
        AstClass* const cp = VN_CAST(classp, Class);
        if (!cp || !cp->extendsp()) return nullptr;
        classp = cp->extendsp()->classp();
    }
    return nullptr;
}

// Walk up the extends chain from classp to find the nearest ancestor (starting
// with classp itself) that has its own persistent VlRandomizer generator
// variable (stored in AstClass::user3p()). That is normally classp itself, or
// otherwise the base-most class, since createRandomGenerator() only creates
// one on a class that owns class-level constraints; a purely-derived class
// with no constraints of its own has no user3p() and defers to its base.
static AstVar* getRandomGenerator(AstClass* const classp) {
    if (classp->user3p()) return VN_AS(classp->user3p(), Var);
    if (classp->extendsp()) return getRandomGenerator(classp->extendsp()->classp());
    return nullptr;
}

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

// Create __Vsetup_constraints function if non existant inside memberMap,
// if existant return one already present
static AstTask* getCreateConstraintSetupFunc(AstClass* classp, VMemberMap& memberMap) {
    static const char* const name = "__Vsetup_constraints";
    AstTask* setupAllTaskp = VN_AS(memberMap.findMember(classp, name), Task);
    if (setupAllTaskp) return setupAllTaskp;
    setupAllTaskp = new AstTask{classp->fileline(), "__Vsetup_constraints", nullptr};
    setupAllTaskp->classMethod(true);
    setupAllTaskp->isVirtual(true);
    classp->addMembersp(setupAllTaskp);
    memberMap.insert(classp, setupAllTaskp);
    return setupAllTaskp;
}

// ######################################################################
// Establishes the target of a rand_mode() call

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

// SMT constant with the value of nodep
static AstSFormatF* getConstFormat(AstNodeExpr* nodep) {
    return new AstSFormatF{nodep->fileline(), (nodep->width() & 3) ? "#b%b" : "#x%x", false,
                           nodep};
}

// Call f on each field that the solver registers for an element object of class classp
template <typename T_Func>
static void foreachSolverElemField(const AstClass* classp, T_Func f) {
    for (const AstClass* cp = classp; cp;
         cp = cp->extendsp() ? cp->extendsp()->classp() : nullptr) {
        for (AstNode* const mnodep : cp->memberspList()) {
            AstVar* const memberVarp = VN_CAST(mnodep, Var);
            if (!memberVarp || !memberVarp->rand().isRandomizable()) continue;
            const AstNodeDType* const memberDtp = memberVarp->dtypep()->skipRefp();
            if (VN_IS(memberDtp, ClassRefDType) || memberDtp->isNonPackedArray()) continue;
            f(memberVarp);
        }
    }
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

// ######################################################################
// Stores info about a variable's rand_mode state/a constraint's constraint_mode state

union RandomizeMode final {
    // MEMBERS
    struct {
        bool usesMode : 1;  // Variable/constraint uses rand_mode/constraint_mode
        uint32_t index : 31;  // Index of var/constraint in rand_mode/constraint_mode vector
    };
    uint64_t asUQuad;  // Representation as int to be stored in nodep->user*
};

// Look through unpacked array dimensions to the element type
static AstNodeDType* arrayElementDTypep(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefToEnump();
    while (dtypep->isNonPackedArray()) dtypep = dtypep->subDTypep()->skipRefToEnump();
    return dtypep;
}

// Offset of the element at declared index idxp of array arrDtp, as selects and the solver use
static AstNodeExpr* newElemOffsetp(FileLine* const fl, const AstNodeDType* const arrDtp,
                                   AstNodeExpr* const idxp) {
    const AstUnpackArrayDType* const unpackDtp = VN_CAST(arrDtp->skipRefp(), UnpackArrayDType);
    if (!unpackDtp) return idxp;
    AstNodeExpr* const offsetp
        = new AstSub{fl, idxp, new AstConst{fl, static_cast<uint32_t>(unpackDtp->lo())}};
    offsetp->dtypeSetUInt32();
    return offsetp;
}

// Element of array arrp at declared index idxVarp
static AstNodeExpr* newIdxSelp(FileLine* const fl, AstNodeExpr* const arrp,
                               AstVar* const idxVarp) {
    AstNodeDType* const arrDtp = arrp->dtypep()->skipRefp();
    // foreach gives the declared index, a select takes the offset
    AstNodeExpr* const offsetp
        = newElemOffsetp(fl, arrDtp, new AstVarRef{fl, idxVarp, VAccess::READ});
    AstNodeExpr* selp;
    if (VN_IS(arrDtp, UnpackArrayDType)) {
        selp = new AstArraySel{fl, arrp, offsetp};
    } else {
        selp = new AstCMethodHard{fl, arrp, VCMethod::ARRAY_AT, offsetp};
    }
    selp->dtypep(arrDtp->subDTypep());
    return selp;
}
// Element of array arrp at the declared indices idxVarps, one for each dimension
static AstNodeExpr* newElemSelp(FileLine* const fl, AstNodeExpr* arrp,
                                const std::vector<AstVar*>& idxVarps) {
    for (AstVar* const idxVarp : idxVarps) arrp = newIdxSelp(fl, arrp, idxVarp);
    return arrp;
}

// Whether varp is an unpacked array of class handles
static bool isClassHandleArray(AstVar* varp) {
    return varp->dtypep()->skipRefp()->isNonPackedArray()
           && VN_IS(arrayElementDTypep(varp->dtypep()), ClassRefDType);
}

// Static rand_mode array of classp, which may be declared by a base class
static AstVar* findStaticRandModeVar(VMemberMap& memberMap, AstClass* classp) {
    while (true) {
        if (AstVar* const varp = VN_CAST(memberMap.findMember(classp, "__Vstaticrandmode"), Var)) {
            return varp;
        }
        AstClassExtends* const extendsp = classp->extendsp();
        if (!extendsp) return nullptr;
        classp = extendsp->classp();
    }
}

// A constraint made by cloning the constraint of an object, or of the objects of an array
struct ClonedConstraint final {
    AstNodeExpr* objp;  // The object, or object array, it was cloned for
    AstConstraint* origp;  // The constraint it was cloned from
};
using ClonedConstraints = std::map<const AstConstraint*, ClonedConstraint>;

// Whether the handles on the path objp have rand_mode on (if modes) and are not null (if
// nonNull), nullptr if nothing to check
static AstNodeExpr* newHandlesActivep(VMemberMap& memberMap, AstNodeExpr* objp, bool modes,
                                      bool nonNull) {
    // The object of an inactive (IEEE 1800-2023 18.8) or null (18.4) handle is not
    // randomized. objp is a chain of member and element selects from a member of 'this'.
    AstNodeExpr* condp = nullptr;
    while (objp) {
        if (AstNodeSel* const nodeSelp = VN_CAST(objp, NodeSel)) {
            objp = nodeSelp->fromp();  // An element
            continue;
        }
        if (AstCMethodHard* const atp = VN_CAST(objp, CMethodHard)) {
            objp = atp->fromp();  // An element
            continue;
        }
        AstMemberSel* const selp = VN_CAST(objp, MemberSel);
        const AstVar* const varp = selp ? selp->varp() : VN_AS(objp, VarRef)->varp();
        AstNodeExpr* const ownerp = selp ? selp->fromp() : nullptr;  // nullptr: 'this'
        FileLine* const fl = objp->fileline();
        AstNodeExpr* levelp = nullptr;  // Checks of this handle, after those of its owner
        if (nonNull && VN_IS(varp->dtypep()->skipRefp(), ClassRefDType)) {
            levelp = new AstNeq{fl, objp->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
        }
        const RandomizeMode mode = {.asUQuad = varp->user1()};
        // Of a rand member, not the mode of a randomize() argument
        if (modes && varp->isRand() && mode.usesMode) {
            // The mode of a static handle is in its class's static array
            const bool isStatic = varp->lifetime().isStatic();
            AstVar* const modeVarp
                = isStatic ? findStaticRandModeVar(memberMap, VN_AS(varp->user2p(), Class))
                           : getRandModeVarFromClass(VN_AS(varp->user2p(), NodeModule));
            AstNodeExpr* modesp;
            if (ownerp && !isStatic) {
                modesp = new AstMemberSel{fl, ownerp->cloneTree(false), modeVarp};
                modesp->dtypep(modeVarp->dtypep());
            } else {
                modesp = new AstVarRef{fl, VN_AS(modeVarp->user2p(), NodeModule), modeVarp,
                                       VAccess::READ};
            }
            AstCMethodHard* const atp
                = new AstCMethodHard{fl, modesp, VCMethod::ARRAY_AT, new AstConst{fl, mode.index}};
            atp->dtypeSetUInt32();
            levelp = levelp ? new AstLogAnd{fl, levelp, atp} : static_cast<AstNodeExpr*>(atp);
        }
        if (levelp) condp = condp ? new AstLogAnd{fl, levelp, condp} : levelp;
        objp = ownerp;
    }
    return condp;
}

// Whether any operand of nodep depends on a randomized variable
static bool operandsRand(const AstNode* nodep) {
    return (nodep->op1p() && nodep->op1p()->user1()) || (nodep->op2p() && nodep->op2p()->user1())
           || (nodep->op3p() && nodep->op3p()->user1())
           || (nodep->op4p() && nodep->op4p()->user1());
}

// Whether an array index depends on a variable being randomized
static bool isRandIndex(const AstNodeExpr* indexp) {
    // Not user1, which can be over-marked in sum/with expansion contexts. A std::randomize()
    // with-clause argument carries no rand qualifier of its own but is still part of the solve.
    return indexp->exists([](const AstNodeVarRef* const vrefp) {
        return vrefp->varp()->rand().isRandomizable() || vrefp->varp()->isStdRandomizeArg();
    });
}

// Return the index of an array element select
static AstNodeExpr* selIndexp(AstNode* selp) {
    if (AstNodeSel* const nodeSelp = VN_CAST(selp, NodeSel)) return nodeSelp->bitp();
    return VN_AS(selp, CMethodHard)->pinsp();
}

// Return the random index select into a non-random array that exprp reads through
static AstNodeExpr* randIndexSelp(AstNodeExpr* exprp,
                                  bool (*isRandIndexp)(const AstNodeExpr* indexp)) {
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

// SMT name of a variable reference or of a member select chain rooted at one
static std::string buildMemberPath(const AstNodeExpr* const exprp) {
    if (const AstVarRef* const refp = VN_CAST(exprp, VarRef)) return refp->name();
    const AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel);
    UASSERT_OBJ(memberSelp, exprp, "Unexpected node type in MemberSel chain");
    return buildMemberPath(memberSelp->fromp()) + "." + memberSelp->name();
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

// Whether dtypep is an array of arrays whose elements are class handles
static bool isMultiDimHandleArray(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefp();
    return dtypep->isNonPackedArray() && dtypep->subDTypep()->skipRefp()->isNonPackedArray()
           && VN_IS(arrayElementDTypep(dtypep), ClassRefDType);
}

// Whether dtypep is, or contains anywhere through unpacked array/struct
// nesting, a real value. A packed struct can't hold one (IEEE disallows
// real as a packed-struct member), so it's never worth descending into.
static bool dtypeContainsReal(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefp();
    if (AstNodeDType* const subp = dtypep->subDTypep()) return dtypeContainsReal(subp);
    if (const AstNodeUOrStructDType* const structp = VN_CAST(dtypep, NodeUOrStructDType)) {
        if (structp->packed()) return false;
        for (AstMemberDType* const memberp : structp->memberspList()) {
            if (dtypeContainsReal(memberp->subDTypep())) return true;
        }
        return false;
    }
    const AstBasicDType* const basicp = VN_CAST(dtypep, BasicDType);
    return basicp && basicp->isDouble();
}

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
                    const AstClassRefDType* const classRefp
                        = VN_CAST(arrayElementDTypep(varp->dtypep()), ClassRefDType);
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
            = VN_AS(arrayElementDTypep(arrVarp->dtypep()), ClassRefDType);
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
            AstNodeExpr* const elemp = newElemSelp(fl, arrRefp->cloneTree(false), idxVarps);
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
        } else if (randIndexSelp(nodep->fromp(), isMarkedRandIndex)) {
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

//######################################################################
// Constraint item calling a function with random arguments (IEEE 1800-2023 18.5.11)

struct ConstraintFuncCall final {
    FileLine* fileline;  // Location of the constraint item
    std::set<std::string> argNames;  // Solver names of the random function arguments
    std::set<std::string> otherNames;  // Solver names of the item's other random variables
};

//######################################################################
// Solve rounds for functions called in constraints (IEEE 1800-2023 18.5.11)

class ConstraintFuncRounds final {
    // Random variables passed to a function are solved before the other random variables of
    // the constraint item calling it. Each function argument is solved in the round after the
    // latest round of the arguments it depends on, then fixed; the final round solves the rest.
    static constexpr int VISITING = -1;  // Round of a variable whose round is being computed
    std::map<std::string, std::vector<const ConstraintFuncCall*>>
        m_callsUsing;  // Variable -> items using it outside of function arguments
    std::map<std::string, int> m_rounds;  // Function argument -> its round
    int m_lastRound = 0;  // Final round, 0 if no rounds are needed
    bool m_circular = false;  // Found a circular dependency

    int roundOf(const std::string& name, const ConstraintFuncCall& call) {
        const auto pair = m_rounds.emplace(name, VISITING);
        if (!pair.second) {
            if (pair.first->second == VISITING) {
                m_circular = true;
                call.fileline->v3error("Circular dependency between random variables passed to "
                                       "functions in constraints (IEEE 1800-2023 18.5.11): '"
                                       << name << "'");
            }
            return pair.first->second;
        }
        int round = 0;
        for (const ConstraintFuncCall* const callp : m_callsUsing[name]) {
            for (const std::string& argName : callp->argNames) {
                round = std::max(round, roundOf(argName, *callp) + 1);
            }
        }
        pair.first->second = round;
        return round;
    }

public:
    explicit ConstraintFuncRounds(const std::vector<ConstraintFuncCall>& calls) {
        for (const ConstraintFuncCall& call : calls) {
            for (const std::string& name : call.otherNames) {
                // A function argument used directly in the same item is solved first as well
                if (!call.argNames.count(name)) m_callsUsing[name].push_back(&call);
            }
        }
        for (const ConstraintFuncCall& call : calls) {
            for (const std::string& name : call.argNames) {
                m_lastRound = std::max(m_lastRound, roundOf(name, call) + 1);
            }
        }
        if (m_circular) m_lastRound = 0;
    }
    int lastRound() const { return m_lastRound; }
    // C++ initializer list of each function argument and its round
    std::string roundList() const {
        std::string list;
        for (const auto& pair : m_rounds) {
            list += (list.empty() ? "{{\"" : ", {\"") + pair.first + "\", "
                    + std::to_string(pair.second) + "}";
        }
        return list + "}";
    }
};

//######################################################################
// Visitor that turns constraints into template strings for solvers

class ConstraintExprVisitor final : public VNVisitor {
    // NODE STATE
    // AstVar::user3() -> bool. Handled in constraints
    // AstNodeExpr::user1()    -> bool. Depending on a randomized variable
    // AstMemberSel::user2p()  -> AstNodeModule*. Pointer to containing module
    // VNuser3InUse m_inuser3; (Allocated for use in RandomizeVisitor)

    AstClass* const m_classp;  // Class being processed
    AstBegin* const m_inlineInitBlockp;  // Block to add write_var calls to
                                         // (may be null, then new() is used)
    AstNodeFTask* const m_memberselInitTaskp;  // Setup of the constraint, for membersel
                                               // write_var
    AstVar* const m_genp;  // VlRandomizer variable of the class
    AstVar* m_randModeVarp;  // Relevant randmode state variable
    bool m_wantSingle = false;  // Whether to merge constraint expressions with LOGAND
    VMemberMap& m_memberMap;  // Member names cached for fast lookup
    bool m_structSel = false;  // Marks when inside structSel
                               // (used to format "%s.%s" for struct arrays and nested structs)
    bool m_deferRandModeHoist = false;  // Wait for the complete struct member path
    std::set<std::string>& m_writtenVars;  // Track which variable paths have write_var generated
                                           // (shared across all constraints)
    // Variables registered in new() of their class (user3() is also set by a member select
    // registration, which does not register the variable for its own class)
    std::set<const AstVar*>* const m_newWrittenVarsp;
    std::set<std::string> m_inlineWrittenVars;  // Per-instance tracking for inline constraints
    VInsertionSet<AstVar*>* m_sizeConstrainedArraysp = nullptr;  // Arrays with size constraints
    AstNodeExpr* m_conditionp = nullptr;  // Condition under which current expression is defined
                                          // (nullptr == always defined)
    const AstArraySel* m_inRangeSelp = nullptr;  // Select already guarded by its range check
    AstNodeFTask* m_prepareConstrainedArraysp = nullptr;  // Grow arrays for indexed struct access
    uint32_t* m_uniqueConstraintIdp = nullptr;  // Current ID of unique call
    V3UniqueNames& m_uniqueNames;  // Unique names of temporaries, and of blocks holding them
    // First expression found under an inside index
    AstNode* m_firstExpressionInsideIndexp = nullptr;
    AstConstraintForeach* m_foreachp = nullptr;  // Innermost constraint-foreach being processed
    std::set<const AstVar*> m_foreachIdxVars;  // Index vars of all enclosing constraint-foreaches
    // Solver variables named by constraints folded into a single expression (m_wantSingle)
    // by a top-level if; empty except between that fold and m_foldTakerp taking them over
    std::set<std::string> m_constraintVars;
    // Constraint replacing the top-level if whose folded names m_constraintVars holds
    const AstConstraintExpr* m_foldTakerp = nullptr;
    struct GuardItem final {
        AstVar* errorVarp = nullptr;  // Out-of-band ERROR of this active constraint item
    };
    GuardItem* m_guardItemp = nullptr;  // Shared by nested formatting within one item
    AstVar* m_foldErrorVarp = nullptr;  // Error status taken over with m_foldTakerp
    // Where the variable references being lowered record their solver names. Set by
    // visit(AstConstraintExpr*), the only visit reaching a variable reference: the other
    // constraint items either move their expressions into one or never iterate them.
    std::set<std::string>* m_constraintVarsp = nullptr;
    bool m_inFuncArg = false;  // Registering the random variables of a function argument
    std::set<std::string> m_funcArgNames;  // Random function arguments in the current item
    std::set<std::string> m_itemVarNames;  // Other random variables in the current item
    std::vector<ConstraintFuncCall> m_funcCalls;  // Items calling functions with random arguments
    // Condition that the arrays reduced in the current constraint keep their current sizes
    AstNodeExpr* m_sizeGatep = nullptr;

    class NestedAccessPath final {
        AstMemberSel* m_topNestedArrayMemberSelp
            = nullptr;  // Top node of nested array/member access
        AstSFormatF* m_nestedNameFormatTopp = nullptr;  // Top node of variable's name format
        AstSFormatF* m_nestedNameFormatp = nullptr;  // Last node of variable's name format
        AstNode** m_firstExpressionInsideIndexPointerp
            = nullptr;  // First expression with no name, used for "Multiple expressions inside
                        // indices of complex expression in constraint" error

        std::string m_smtName;  // string name for shouldWriteVar checking

    public:
        void addVarNamePart(AstSFormatF* const nodep, std::string&& name) {
            if (!m_nestedNameFormatp) {
                m_nestedNameFormatTopp = nodep;
                m_nestedNameFormatp = m_nestedNameFormatTopp;
            } else {
                m_nestedNameFormatp->prependExprsp(nodep);
            }
            m_nestedNameFormatp = nodep;

            m_smtName.insert(0, "." + name);
            // Some expressions have empty name which can cause some variables to have the same
            // name and only first one will be written
            if (name == "") {
                if (*m_firstExpressionInsideIndexPointerp) {
                    (*m_firstExpressionInsideIndexPointerp)
                        ->v3warn(
                            E_UNSUPPORTED,
                            "Unsupported: Multiple expressions inside indices of complex "
                            "expression in constraint\n"
                                << (*m_firstExpressionInsideIndexPointerp)->warnContextPrimary()
                                << nodep->warnOther() << "... Location of second expression\n"
                                << nodep->warnContextSecondary());
                }
                *m_firstExpressionInsideIndexPointerp = nodep;
            }
        }

        AstMemberSel* accessTree() { return m_topNestedArrayMemberSelp; }
        const std::string& smtName() { return m_smtName; }

        AstStmtExpr* makeWriteVarStmt(AstVar* varp, AstVar* genp) {
            AstCMethodHard* const methodp = new AstCMethodHard{
                varp->fileline(),
                new AstVarRef{varp->fileline(), VN_AS(genp->user2p(), NodeModule), genp,
                              VAccess::READWRITE},
                VCMethod::RANDOMIZER_WRITE_VAR};
            methodp->dtypeSetVoid();

            methodp->addPinsp(m_topNestedArrayMemberSelp);  // Variable

            const AstNodeDType* const dtypep = varp->dtypep();  // Width
            const size_t width = m_topNestedArrayMemberSelp->varp()->dtypep()->width();
            methodp->addPinsp(new AstConst{dtypep->fileline(), AstConst::Unsized64{}, width});

            methodp->addPinsp(m_nestedNameFormatTopp);  // Solver name
            m_nestedNameFormatp = nullptr;

            methodp->addPinsp(
                new AstConst{dtypep->fileline(), AstConst::Unsized64{}, 0});  // Dimension

            m_topNestedArrayMemberSelp = nullptr;
            return methodp->makeStmt();
        }

        AstNodeExpr* cloneName() { return m_nestedNameFormatTopp->cloneTree(false); }

        void error() {
            VL_DO_DANGLING(m_topNestedArrayMemberSelp->deleteTree(), m_topNestedArrayMemberSelp);
        }

        NestedAccessPath(AstMemberSel* topMemberSelp, AstNode** pointerToFirstExprp)
            : m_topNestedArrayMemberSelp{topMemberSelp}
            , m_firstExpressionInsideIndexPointerp{pointerToFirstExprp} {}
        ~NestedAccessPath() {
            if (m_nestedNameFormatp) {
                VL_DO_CLEAR(m_nestedNameFormatTopp->deleteTree(),
                            m_nestedNameFormatTopp = nullptr);
                m_nestedNameFormatp = nullptr;
            }
        }
    };
    NestedAccessPath* m_nestedAccessp = nullptr;  // Indicates state of nested access

    // Mark the one directly-referenced member; it must reach the solver even when it
    // carries no rand qualifier (the constraint refers to it).
    void markConstrainedRandMember(AstStructDType* const structp, const std::string& name) {
        AstMemberDType* const memberp
            = VN_CAST(m_memberMap.findMember(structp, name), MemberDType);
        UASSERT_OBJ(memberp, structp, "Constraint references unknown struct member " << name);
        memberp->markConstrainedRand(true);
    }

    // True when the aggregate is reached through rand-qualified struct members only
    bool isRandQualifiedPath(const AstNodeExpr* nodep) {
        while (nodep) {
            if (const AstStructSel* const selp = VN_CAST(nodep, StructSel)) {
                if (AstStructDType* const structp
                    = VN_CAST(selp->fromp()->dtypep()->skipRefp(), StructDType)) {
                    const AstMemberDType* const memberp
                        = VN_CAST(m_memberMap.findMember(structp, selp->name()), MemberDType);
                    if (memberp && !memberp->rand().isRandomizable()) return false;
                }
                nodep = selp->fromp();
            } else if (const AstArraySel* const selp = VN_CAST(nodep, ArraySel)) {
                nodep = selp->fromp();
            } else if (const AstCMethodHard* const methodp = VN_CAST(nodep, CMethodHard)) {
                nodep = methodp->fromp();
            } else {
                break;
            }
        }
        return true;
    }

    // IEEE 1800-2023 18.4: all rand members of a rand unpacked struct are solved
    // concurrently, so unreferenced rand members must still reach the solver.
    static void markStructConstrainedRandRecurse(AstNodeDType* const dtypep) {
        AstStructDType* const structp = VN_CAST(arrayElementDTypep(dtypep), StructDType);
        if (!structp || structp->packed()) return;
        structp->markConstrainedRand(true);
        for (AstMemberDType* const memberp : structp->memberspList()) {
            // Non-rand members keep their value. TODO: randc members are solved as
            // plain rand (uniform); per-member cyclic state is not generated for structs.
            if (!memberp->rand().isRandomizable()) continue;
            memberp->markConstrainedRand(true);
            markStructConstrainedRandRecurse(memberp->subDTypep());
        }
    }

    // C++ initializer list of the recorded symbols
    static std::string constraintVarsList(const std::set<std::string>& vars) {
        std::string list = "{";
        for (const std::string& name : vars) {
            if (list.size() > 1) list += ", ";
            list += "\"" + name + "\"";
        }
        return list + "}";
    }

    static AstNodeExpr* getFromp(const AstNodeExpr* const nodep) {
        if (const AstCMethodHard* const cmethp = VN_CAST(nodep, CMethodHard)) {
            return cmethp->fromp();
        }
        return getSelFromp(nodep);
    }

    static std::string extractSolveBeforeBaseName(const AstNodeExpr* exprp) {
        while (const AstNodeExpr* const fromp = getFromp(exprp)) exprp = fromp;
        if (const AstVarRef* const vrefp = VN_CAST(exprp, VarRef)) return vrefp->name();
        return "";
    }

    static void buildNamePrefix(AstCExpr* exprp, const AstNodeExpr* const nodep) {
        if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
            exprp->add("(\""s + refp->name());
            return;
        }

        const AstNodeExpr* const fromp = getFromp(nodep);
        if (fromp) buildNamePrefix(exprp, fromp);

        // A member of a member object chain (e.g. 'r.c.x' in a global constraint) is
        // registered with its dotted path, as a struct member is
        if (VN_IS(nodep, StructSel)
            || (VN_IS(nodep, MemberSel) && (VN_IS(fromp, VarRef) || VN_IS(fromp, MemberSel)))) {
            exprp->add("." + nodep->name());
        } else if (VN_IS(nodep, MemberSel)) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: Nested array element access in global constraint");
            return;
        } else if (const AstCMethodHard* const cmethp = VN_CAST(nodep, CMethodHard)) {
            if (cmethp->method() == VCMethod::ARRAY_AT) {
                AstNodeExpr* const argp = cmethp->pinsp();
                exprp->add(".\" + ");
                AstCFuncHard* const solverHexFuncp
                    = new AstCFuncHard{nodep->fileline(), VCFunction::RANDOMIZER_TO_SOLVER_HEX};
                solverHexFuncp->addPinsp(argp->cloneTreePure(false));
                solverHexFuncp->dtypeSetString();
                exprp->add(solverHexFuncp);
                exprp->add(" + \"");
            } else {
                cmethp->v3fatalSrc("Unexpected CMethodHard: " << cmethp->prettyTypeName());
                return;
            }
        }
    }

    // Build a C++ expression (as AstNodeExpr) that evaluates to a const char*
    // containing the SMT variable name for a solve-before variable reference.
    // Handles simple vars, struct selects, and array element selects (for foreach).
    static AstCExpr* buildPathExpr(FileLine* const fl, const AstNodeExpr* nodep,
                                   const std::string selName) {
        AstCExpr* const exprp = new AstCExpr{fl, ""};
        buildNamePrefix(exprp, nodep);
        if (selName != "") {
            exprp->add(".");
            exprp->add(selName);
        }
        exprp->add("\")");
        return exprp;
    }
    // Array and index of element select selp, a NodeSel or ARRAY_AT, else nullptr
    static AstNodeExpr* elemSelFromp(const AstNode* selp, AstNodeExpr*& indexpr) {
        if (const AstNodeSel* const nodeSelp = VN_CAST(selp, NodeSel)) {
            indexpr = nodeSelp->bitp();
            return nodeSelp->fromp();
        }
        const AstCMethodHard* const atp = VN_CAST(selp, CMethodHard);
        if (!atp) return nullptr;
        UASSERT_OBJ(atp->method() == VCMethod::ARRAY_AT, atp, "Unexpected method in a select");
        indexpr = atp->pinsp();
        return atp->fromp();
    }
    // Build a C++ expression (as AstNodeExpr) that evaluates to a const char*
    // containing the SMT variable name for a solve-before variable reference.
    // Handles simple vars, member selects, and array element selects (for foreach).
    // Returns nullptr for unsupported expression types.
    // Helper: build a dynamic AstCExpr for "baseName[idx]" pattern of element select selp
    // (see elemSelFromp), nullptr if unsupported
    AstCExpr* buildArraySelNameExpr(FileLine* fl, const AstNodeExpr* selp) {
        AstNodeExpr* indexp = nullptr;
        AstNodeExpr* const fromp = elemSelFromp(selp, indexp);
        AstNodeExpr* fromIndexp = nullptr;
        AstCExpr* prefixp = nullptr;  // Name of the array
        if (elemSelFromp(fromp, fromIndexp)) {
            prefixp = buildArraySelNameExpr(fl, fromp);  // Of a multi-dimensional array
        } else if (const AstVarRef* const vp = VN_CAST(fromp, VarRef)) {
            prefixp = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + vp->name() + "\"s"};
        } else if (const AstMemberSel* const mp = VN_CAST(fromp, MemberSel)) {
            prefixp = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + buildMemberPath(mp) + "\"s"};
        }
        if (!prefixp) return nullptr;
        prefixp->dtypeSetString();
        AstCExpr* const p = new AstCExpr{fl, "("};
        p->add(prefixp);
        p->add(" + \".\" + ");
        AstCFuncHard* const solverHexFuncp
            = new AstCFuncHard{fl, VCFunction::RANDOMIZER_TO_SOLVER_HEX};
        solverHexFuncp->addPinsp(indexp->cloneTreePure(false));
        solverHexFuncp->dtypeSetString();
        p->add(solverHexFuncp);
        p->add(")");
        p->dtypeSetString();
        return p;
    }

    // Helper: get fromp from MemberSel or StructSel
    static AstNodeExpr* getSelFromp(const AstNodeExpr* exprp) {
        if (const AstMemberSel* const mp = VN_CAST(exprp, MemberSel)) return mp->fromp();
        if (const AstStructSel* const sp = VN_CAST(exprp, StructSel)) return sp->fromp();
        return nullptr;
    }

    AstNodeExpr* buildSolveBeforeNameExpr(FileLine* fl, AstNodeExpr* exprp) {
        if (const AstVarRef* const varrefp = VN_CAST(exprp, VarRef)) {
            AstCExpr* const p = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + varrefp->name() + "\"s"};
            p->dtypeSetString();
            return p;
        }
        // Handle MemberSel or StructSel (V3Width converts MemberSel -> StructSel for structs)
        if (AstNodeExpr* const selFromp = getSelFromp(exprp)) {
            const std::string selName = exprp->name();
            // Check if fromp chain contains ArraySel (e.g., cfg[i].w)
            if (const AstArraySel* const arrSelp = VN_CAST(selFromp, ArraySel)) {
                return buildArraySelNameExpr(fl, arrSelp);
            }
            // Static member path (obj.field)
            if (const AstVarRef* const vp = VN_CAST(selFromp, VarRef)) {
                const std::string path = vp->name() + "." + selName;
                AstCExpr* const p = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + path + "\"s"};
                p->dtypeSetString();
                return p;
            }
            if (VN_IS(selFromp, MemberSel) || VN_IS(selFromp, StructSel)
                || VN_IS(selFromp, CMethodHard)) {
                AstCExpr* const p = buildPathExpr(fl, selFromp, selName);
                p->dtypeSetString();
                return p;
            }
            return nullptr;
        }
        if (VN_IS(exprp, CMethodHard)) {
            AstCExpr* const p = buildPathExpr(fl, exprp, "");
            p->dtypeSetString();
            return p;
        }
        const AstNodeSel* selp = VN_CAST(exprp, ArraySel);
        if (!selp) selp = VN_CAST(exprp, AssocSel);
        if (selp) return buildArraySelNameExpr(fl, selp);  // arr[i] -> dynamic name
        // Packed struct member: SEL(ARRAYSEL(...)) -- bit select on array element.
        // Solver registers the whole element, so promote to array element level.
        if (const AstSel* const bitSelp = VN_CAST(exprp, Sel)) {
            return buildSolveBeforeNameExpr(fl, bitSelp->fromp());
        }
        return nullptr;
    }

    bool editFormat(AstNodeExpr* nodep) {
        if (nodep->user1()) return editStateArraySel(nodep);
        // Replace computable expression with SMT constant
        VNRelinker handle;
        nodep->unlinkFrBack(&handle);
        handle.relink(getConstFormat(nodep));
        return true;
    }
    // Make the current constraint hold only while a solver-sized array keeps its size
    void gateOnCurrentSize(AstNodeExpr* arrayp) {
        // A reduction of the array, or an 'inside' it, is expanded over the elements the array
        // has when the constraints are set up. A dynamic array or queue with a size constraint
        // is solved twice: first for its new size (IEEE 1800-2023 18.5.8.1: size constraints
        // are solved before iterative ones) while it still has its previous size, then resized
        // and solved with the size pinned. So the expansion is only right in the first solve
        // if that keeps the previous size, and must not constrain any other.
        AstVarRef* const arrRefp = VN_CAST(arrayp, VarRef);
        if (!arrRefp) return;
        AstVar* const arrVarp = arrRefp->varp();
        AstVar* const sizeVarp = VN_CAST(arrVarp->user4p(), Var);
        if (!sizeVarp || VN_IS(arrVarp->dtypep()->skipRefp(), AssocArrayDType)) return;
        FileLine* const fl = arrRefp->fileline();
        AstVarRef* const sizeRefp
            = new AstVarRef{fl, VN_AS(sizeVarp->user2p(), NodeModule), sizeVarp, VAccess::READ};
        sizeRefp->user1(true);
        AstCMethodHard* const curSizep
            = new AstCMethodHard{fl, arrRefp->cloneTree(false), VCMethod::DYN_SIZE};
        curSizep->dtypeFrom(sizeVarp);
        AstEq* const eqp = new AstEq{fl, sizeRefp, curSizep};
        eqp->user1(true);
        if (m_sizeGatep) {
            m_sizeGatep = new AstLogAnd{fl, m_sizeGatep, eqp};
            m_sizeGatep->user1(true);
        } else {
            m_sizeGatep = eqp;
        }
        // Solve twice even if no element is referenced, e.g. with only 'item.index'
        if (m_sizeConstrainedArraysp) m_sizeConstrainedArraysp->insert(arrVarp);
    }
    AstNodeExpr* wrapWithCond(AstNodeExpr* const exprp, AstNodeExpr* const condp,
                              const int width) {
        if (condp) {
            FileLine* const flp = exprp->fileline();
            return new AstCond{
                flp, condp, exprp,
                getConstFormat(new AstConst{flp, AstConst::WidthedValue{}, width, 0})};
        }
        return exprp;
    }
    AstSFormatF* editSMT(AstNodeExpr* nodep, AstNodeExpr* lhsp = nullptr,
                         AstNodeExpr* rhsp = nullptr, AstNodeExpr* thsp = nullptr) {
        // Replace incomputable (result-dependent) expression with SMT expression
        std::string smtExpr = nodep->emitSMT();  // Might need child width (AstExtend)
        if (smtExpr == "") {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported expression inside constraint");
            return nullptr;
        }

        const int lhsWidth = lhsp ? lhsp->width() : 0;
        const int rhsWidth = rhsp ? rhsp->width() : 0;
        const int thsWidth = thsp ? thsp->width() : 0;
        AstNodeExpr* lhsCondp = nullptr;
        AstNodeExpr* rhsCondp = nullptr;
        AstNodeExpr* thsCondp = nullptr;

        if (lhsp) {
            VL_RESTORER(m_conditionp);
            m_conditionp = nullptr;
            lhsp = VN_AS(iterateSubtreeReturnEdits(lhsp->backp() ? lhsp->unlinkFrBack() : lhsp),
                         NodeExpr);
            lhsCondp = m_conditionp;
        }
        if (rhsp) {
            VL_RESTORER(m_conditionp);
            m_conditionp = nullptr;
            rhsp = VN_AS(iterateSubtreeReturnEdits(rhsp->backp() ? rhsp->unlinkFrBack() : rhsp),
                         NodeExpr);
            rhsCondp = m_conditionp;
        }
        if (thsp) {
            VL_RESTORER(m_conditionp);
            m_conditionp = nullptr;
            thsp = VN_AS(iterateSubtreeReturnEdits(thsp->backp() ? thsp->unlinkFrBack() : thsp),
                         NodeExpr);
            thsCondp = m_conditionp;
        }

        AstNodeExpr* argsp = nullptr;
        for (string::iterator pos = smtExpr.begin(); pos != smtExpr.end(); ++pos) {
            if (pos[0] == '%') {
                ++pos;
                switch (pos[0]) {
                case '%': break;
                case 'l':
                    pos[0] = 's';
                    UASSERT_OBJ(lhsp, nodep, "emitSMT() references undef node");
                    argsp = AstNode::addNext(argsp, wrapWithCond(lhsp, lhsCondp, lhsWidth));
                    lhsp = nullptr;
                    break;
                case 'r':
                    pos[0] = 's';
                    UASSERT_OBJ(rhsp, nodep, "emitSMT() references undef node");
                    argsp = AstNode::addNext(argsp, wrapWithCond(rhsp, rhsCondp, rhsWidth));
                    rhsp = nullptr;
                    break;
                case 't':
                    pos[0] = 's';
                    UASSERT_OBJ(thsp, nodep, "emitSMT() references undef node");
                    argsp = AstNode::addNext(argsp, wrapWithCond(thsp, thsCondp, thsWidth));
                    thsp = nullptr;
                    break;
                default: nodep->v3fatalSrc("Unknown emitSMT format code: %" << pos[0]); break;
                }
            }
        }
        UASSERT_OBJ(!lhsp, nodep, "Missing emitSMT %l for " << lhsp);
        UASSERT_OBJ(!rhsp, nodep, "Missing emitSMT %r for " << rhsp);
        UASSERT_OBJ(!thsp, nodep, "Missing emitSMT %t for " << thsp);
        AstSFormatF* const newp = new AstSFormatF{nodep->fileline(), smtExpr, false, argsp};

        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        return newp;
    }

    AstNodeExpr* editSingle(FileLine* fl, AstNode* itemsp) {
        if (!itemsp) return nullptr;

        VL_RESTORER(m_wantSingle);
        m_wantSingle = true;

        {
            AstBegin* const tempp
                = new AstBegin{fl, "[EditWrapper]", itemsp->unlinkFrBackWithNext(), false};
            VL_DO_DANGLING(iterateAndNextNull(tempp->stmtsp()), itemsp);
            itemsp = tempp->stmtsp();
            if (itemsp) itemsp->unlinkFrBackWithNext();
            VL_DO_DANGLING(tempp->deleteTree(), tempp);
        }
        if (!itemsp) return nullptr;

        AstNodeExpr* const exprsp = VN_CAST(itemsp, NodeExpr);
        UASSERT_OBJ(exprsp, itemsp, "Single not expression?");

        if (!exprsp->nextp()) return exprsp;

        std::ostringstream fmt;
        fmt << "(bvand";
        for (AstNode* itemp = exprsp; itemp; itemp = itemp->nextp()) fmt << " %s";
        fmt << ')';
        return new AstSFormatF{fl, fmt.str(), false, exprsp};
    }

    AstNodeExpr* newSel(FileLine* fl, AstNodeExpr* arrayp, AstNodeExpr* idxp) {
        // similar to V3WidthSel.cpp
        // skipRefp() unwraps typedef wrappers (AstRefDType) so the dtype kind
        // checks below recognize types spelled as `typedef <scalar> <name>[$]`.
        if (arrayp->backp()) arrayp->unlinkFrBack();
        AstNodeDType* const arrDtp = arrayp->dtypep()->skipRefp();
        AstNodeExpr* selp = nullptr;
        if (VN_IS(arrDtp, QueueDType) || VN_IS(arrDtp, DynArrayDType))
            selp = new AstCMethodHard{fl, arrayp, VCMethod::ARRAY_AT, idxp};
        else if (VN_IS(arrDtp, UnpackArrayDType))
            selp = new AstArraySel{fl, arrayp, idxp};
        else if (VN_IS(arrDtp, AssocArrayDType))
            selp = new AstAssocSel{fl, arrayp, idxp};
        UASSERT_OBJ(selp, arrayp, "Selecting from non-array?");
        selp->dtypep(arrDtp->subDTypep());
        return selp;
    }

    // Whether a reduction cannot iterate over the row array selected by exprp
    static bool unsupportedRowSel(const AstNodeExpr* exprp) {
        // The rows of a queue, dynamic or associative array are not solver variables, and a
        // random index would select a dynamically sized row before solving
        const bool dynRow = !VN_IS(exprp->dtypep()->skipRefp(), UnpackArrayDType);
        while (true) {
            if (const AstArraySel* const selp = VN_CAST(exprp, ArraySel)) {
                if (dynRow && selp->bitp()->exists([](const AstNodeVarRef* refp) {
                        return refp->varp()->rand().isRandomizable();
                    })) {
                    return true;
                }
                exprp = selp->fromp();
            } else if (const AstMemberSel* const selp = VN_CAST(exprp, MemberSel)) {
                exprp = selp->fromp();
            } else if (const AstStructSel* const selp = VN_CAST(exprp, StructSel)) {
                exprp = selp->fromp();
            } else {
                return VN_IS(exprp, AssocSel) || VN_IS(exprp, CMethodHard);
            }
        }
    }

    // Mark the expressions under nodep that depend on a random variable, returning nodep's mark
    static bool markRandDependent(AstNode* nodep) {
        // Needed where 'with' arguments were replaced by array elements and loop indices.
        // Variable references and member selections keep the marks RandomizeMarkVisitor gave
        // them; any other expression is random if an operand is, so the state variables and
        // state array elements in it stay state. Unlike propagateUser1InlineRecurse, which marks
        // a function body RandomizeMarkVisitor never saw, this keeps those marks, as they also
        // depend on context (e.g. std::randomize() arguments, members of a random object).
        bool randOperand = false;
        for (AstNode* const opp : {nodep->op1p(), nodep->op2p(), nodep->op3p(), nodep->op4p()}) {
            for (AstNode* itemp = opp; itemp; itemp = itemp->nextp()) {
                randOperand |= markRandDependent(itemp);
            }
        }
        if (!VN_IS(nodep, NodeVarRef) && !VN_IS(nodep, MemberSel)) nodep->user1(randOperand);
        return nodep->user1();
    }

    // Convert expression to target width using extend or truncate as needed
    AstNodeExpr* adjustWidth(FileLine* fl, AstNodeExpr* exprp, int targetWidth,
                             VSigning targetSigning) {
        const int exprWidth = exprp->width();
        if (targetWidth > exprWidth) {
            // Extend to match target width
            AstNodeExpr* const resultp = new AstExtend{fl, exprp, targetWidth};
            resultp->dtypeChgSigned(targetSigning);
            return resultp;
        } else if (targetWidth < exprWidth) {
            // Truncate to match target width
            AstNodeExpr* const resultp = new AstSel{fl, exprp, 0, targetWidth};
            resultp->dtypeChgSigned(targetSigning);
            return resultp;
        } else {
            // Width already matches
            return exprp;
        }
    }

    // Extract return expression from a simple function body, or nullptr if too complex
    AstNodeExpr* extractReturnExpr(const AstNodeFTaskRef* refp, AstFunc* funcp) {
        // Uses foreach to walk all assigns regardless of body organization (JumpBlock etc.)
        AstVar* const retVarp = VN_CAST(funcp->fvarp(), Var);
        if (!retVarp) return nullptr;
        AstNodeExpr* retExprp = nullptr;
        int retWrites = 0;
        funcp->foreach([&](AstNodeAssign* assignp) {
            // Skip the initializer of an automatic function's return value
            if (VN_IS(assignp->rhsp(), CReset)) return;
            if (!assignp->lhsp()->exists(
                    [&](const AstNodeVarRef* vrefp) { return vrefp->varp() == retVarp; })) {
                return;
            }
            ++retWrites;
            retExprp = VN_IS(assignp->lhsp(), VarRef) ? assignp->rhsp() : nullptr;
        });
        // Simple function: a single assignment of the whole return value
        if (retWrites != 1 || !retExprp) return nullptr;
        std::set<const AstVar*> writtenVarps;
        funcp->foreach([&](const AstNodeVarRef* vrefp) {
            if (vrefp->access().isWriteOrRW()) writtenVarps.emplace(vrefp->varp());
        });
        // The inlined copy is evaluated in the constraint, where the ports read the arguments.
        // Written variables (including all automatic locals, which are initialized), and
        // members of another object than the one randomized, do not have the value the
        // function would see.
        const bool otherObject = VN_IS(refp, MethodCall);
        if (retExprp->exists([&](const AstNodeVarRef* vrefp) {
                const AstVar* const varp = vrefp->varp();
                return writtenVarps.count(varp)
                       || (otherObject && varp->isClassMember() && !varp->lifetime().isStatic());
            })) {
            return nullptr;
        }
        return retExprp;
    }

    // Register the random variables in a function call's arguments, false if unsupported
    bool addFuncArgVars(const AstNodeFTaskRef* nodep) {
        std::vector<AstNodeExpr*> leafps;
        bool supported = true;
        // A call depends on random variables only through its arguments
        nodep->argsp()->foreachAndNext([&](AstNodeVarRef* refp) {
            // A member of a random object, or of the object randomized by 'randomize() with',
            // is random if declared rand
            AstNodeExpr* leafp = refp;
            bool random = refp->user1();
            while (AstMemberSel* const selp = VN_CAST(leafp->backp(), MemberSel)) {
                leafp = selp;
                random |= selp->user1();
            }
            if (const AstMemberSel* const selp = VN_CAST(leafp, MemberSel)) {
                random &= selp->varp()->rand().isRandomizable();
            }
            if (!random) return;
            // Only an integral variable can be solved on its own before the call
            supported &= leafp->dtypep()->skipRefp()->isIntegralOrPacked();
            leafps.push_back(leafp);
        });
        if (!supported) return false;
        VL_RESTORER(m_inFuncArg);
        m_inFuncArg = true;
        for (AstNodeExpr* const leafp : leafps) {
            pushDeletep(iterateSubtreeReturnEdits(leafp->cloneTreePure(false)));
        }
        return true;
    }

    // Bottom-up user1 propagation on inlined expression tree
    void propagateUser1InlineRecurse(AstNodeExpr* nodep) {
        if (VN_IS(nodep, NodeVarRef)) {
            nodep->user1(VN_AS(nodep, NodeVarRef)->varp()->rand().isRandomizable());
            return;
        }
        if (VN_IS(nodep, Const)) {
            nodep->user1(false);
            return;
        }
        if (const AstNodeFTaskRef* const refp = VN_CAST(nodep, NodeFTaskRef)) {
            // A call depends on random variables only through its arguments
            bool anyArg = false;
            for (AstNode* argp = refp->argsp(); argp; argp = argp->nextp()) {
                AstNodeExpr* const exprp = VN_AS(argp, Arg)->exprp();
                propagateUser1InlineRecurse(exprp);
                anyArg |= exprp->user1();
            }
            nodep->user1(anyArg);
            return;
        }
        int anyChild = false;  // Used as bool
        if (AstNodeExpr* const cp = VN_CAST(nodep->op1p(), NodeExpr)) {
            propagateUser1InlineRecurse(cp);
            anyChild |= cp->user1();
        }
        if (AstNodeExpr* const cp = VN_CAST(nodep->op2p(), NodeExpr)) {
            propagateUser1InlineRecurse(cp);
            anyChild |= cp->user1();
        }
        if (AstNodeExpr* const cp = VN_CAST(nodep->op3p(), NodeExpr)) {
            propagateUser1InlineRecurse(cp);
            anyChild |= cp->user1();
        }
        if (AstNodeExpr* const cp = VN_CAST(nodep->op4p(), NodeExpr)) {
            propagateUser1InlineRecurse(cp);
            anyChild |= cp->user1();
        }
        nodep->user1(anyChild);
    }

    // Prepend the bucket preamble stmts stored on user3p by lowerDistConstraints to the
    // statements that will become the body of the generated AstForeach, so the per-element
    // bucket draw is declared and evaluated in the same scope as its references.
    static AstNode* prependDistPreamble(AstConstraintForeach* nodep, AstNode* bodyp) {
        AstNode* const preamblep = nodep->user3p();
        if (!preamblep) return bodyp;
        nodep->user3p(nullptr);
        preamblep->addNext(bodyp);
        return preamblep;
    }

    // True if the statement references an index variable of an enclosing
    // constraint-foreach. Such a statement must stay inside the loop body; hoisting
    // it out leaves a dangling reference once task inlining deletes the index.
    bool referencesForeachIdx(const AstNode* nodep) const {
        if (m_foreachIdxVars.empty()) return false;
        return nodep->exists(
            [&](const AstVarRef* refp) { return m_foreachIdxVars.count(refp->varp()) != 0; });
    }

    AstBegin* newInitBlockp(AstNodeFTask* const taskp) const {
        AstBegin* const blockp = new AstBegin{
            taskp->fileline(), m_uniqueNames.get("__Vconstraint_init"), nullptr, true};
        taskp->addStmtsp(blockp);
        return blockp;
    }

    // Place a solver-registration statement: into the enclosing foreach body when it
    // references an enclosing foreach index (so it is not hoisted out of the index's
    // scope), otherwise into the init block.
    void addRegistrationStmt(AstNode* const stmtp, AstBegin* const initp) {
        if (m_foreachp && referencesForeachIdx(stmtp)) {
            // Appending to the body mid-iteration is safe: visit(AstStmtExpr) is a
            // no-op so the appended node is not re-processed, and prependDistPreamble()
            // correctly keeps it as a loop-body statement.
            m_foreachp->addBodyp(stmtp);
        } else {
            initp->addStmtsp(stmtp);
        }
    }

    // Create SFormatF for array dereference inside solver
    AstSFormatF* createSolverArrDerefp(FileLine* const fl, AstNodeExpr* const arrExprp,
                                       AstNodeExpr* const idxExprp) {
        AstNodeExpr* const argsp = AstNode::addNext(arrExprp, idxExprp);
        AstSFormatF* const formatp = new AstSFormatF{fl, "(select %s %s)", false, argsp};
        return formatp;
    }

    // Return a random array index in the index sort of solver arrays
    static AstNodeExpr* newSmtIndexp(AstNodeExpr* indexp, bool isSigned, int sortWidth = 32) {
        FileLine* const fl = indexp->fileline();
        const int width = indexp->width();
        AstNodeExpr* newp;
        if (width < sortWidth) {
            newp = isSigned ? static_cast<AstNodeExpr*>(new AstExtendS{fl, indexp, sortWidth})
                            : new AstExtend{fl, indexp, sortWidth};
        } else if (width > sortWidth) {
            // An index with any bit set above the sort's width is out of range, so map it to
            // the out of range all-ones index rather than truncate it into range
            AstSel* const highp
                = new AstSel{fl, indexp->cloneTreePure(false), sortWidth, width - sortWidth};
            AstEq* const inRangep = new AstEq{
                fl, highp, new AstConst{fl, AstConst::WidthedValue{}, width - sortWidth, 0}};
            AstSel* const lowp = new AstSel{fl, indexp, 0, sortWidth};
            highp->user1(true);
            inRangep->user1(true);
            lowp->user1(true);
            V3Number allOnes{indexp, sortWidth};
            allOnes.setAllBits1();
            newp = new AstCond{fl, inRangep, lowp, new AstConst{fl, allOnes}};
        } else {
            return indexp;
        }
        newp->user1(true);
        return newp;
    }
    // Width of the SMT index sort of the array selp selects from
    static int smtIndexWidth(AstNode* selp) {
        if (const AstAssocSel* const assocSelp = VN_CAST(selp, AssocSel)) {
            const AstNodeDType* const dtypep = assocSelp->fromp()->dtypep()->skipRefp();
            return keySmtWidth(VN_AS(dtypep, AssocArrayDType)->keyDTypep()->skipRefp());
        }
        return std::max(32, selIndexp(selp)->width());
    }
    // Return an SMT array of the value of exprp at each element of the array selp selects
    AstSFormatF* newIndexedArrayp(AstNodeExpr* exprp, AstNodeExpr* selp) {
        // Element i is exprp with the random index of selp replaced by i, so it may read
        // members of the array element and depend on other random variables. Elements that do
        // not exist read as zero, the default value of a 2-state type (IEEE 1800-2023 7.4.6),
        // which also makes 'inside' a member array of a nonexistent element false, or in an
        // associative array as its default element (7.8.6, 7.9.11). The index
        // of a fixed-size array was already truncated to the width that addresses the array,
        // as in other expressions.
        FileLine* const fl = selp->fileline();
        AstNodeExpr* const arrayp = VN_IS(selp, CMethodHard) ? VN_AS(selp, CMethodHard)->fromp()
                                                             : VN_AS(selp, NodeSel)->fromp();
        const int idxWidth = smtIndexWidth(selp);
        const AstAssocArrayDType* const assocDtp
            = VN_CAST(arrayp->dtypep()->skipRefp(), AssocArrayDType);
        AstVar* const idxVarp
            = new AstVar{fl, VVarType::BLOCKTEMP, "__VarrIdx",
                         assocDtp ? assocDtp->keyDTypep() : arrayp->findIntDType()};
        AstForeachHeader* const headerp
            = new AstForeachHeader{fl, arrayp->cloneTreePure(false), idxVarp};
        // Key is the offset from the low bound, as in ArraySel
        AstNodeExpr* posp = new AstVarRef{fl, idxVarp, VAccess::READ};
        if (const AstUnpackArrayDType* const adtypep
            = VN_CAST(arrayp->dtypep()->skipRefp(), UnpackArrayDType)) {
            posp = new AstSub{fl, posp,
                              new AstConst{fl, AstConst::WidthedValue{}, 32,
                                           static_cast<uint32_t>(adtypep->lo())}};
            posp->dtypeFrom(idxVarp);
        }
        AstNodeExpr* const elemp = exprp->cloneTreePure(false);
        AstNode* const elemSelp = selp->clonep();
        AstNodeExpr* const oldIndexp = selIndexp(elemSelp);
        oldIndexp->replaceWith(posp->cloneTreePure(false));
        VL_DO_DANGLING(oldIndexp->deleteTree(), oldIndexp);
        // The path from elemp down to the element select, through fromp (see randIndexSelp),
        // no longer depends on the index
        std::vector<AstNodeExpr*> pathps;
        for (AstNode* nodep = elemp;; nodep = nodep->op1p()) {
            pathps.push_back(VN_AS(nodep, NodeExpr));
            if (nodep == elemSelp) break;
        }
        // A null handle on the path has no members, so the element reads as zero like a
        // nonexistent one, also for a null handle reached from a member of the element
        AstNodeExpr* nonNullp = nullptr;
        for (auto it = pathps.rbegin(); it != pathps.rend(); ++it) {
            (*it)->user1(operandsRand(*it));
            if (!VN_IS((*it)->dtypep()->skipRefp(), ClassRefDType)) continue;
            AstNodeExpr* const neqp
                = new AstNeq{fl, (*it)->cloneTreePure(false), new AstConst{fl, AstConst::Null{}}};
            nonNullp = nonNullp ? new AstLogAnd{fl, nonNullp, neqp} : neqp;
        }
        const int width = exprp->width();
        AstCStmt* const cstmtp = new AstCStmt{fl};
        cstmtp->add("ret = \"(store \" + ret + \" \" + ");
        cstmtp->add(
            getConstFormat(posp->width() < idxWidth ? new AstExtend{fl, posp, idxWidth} : posp));
        cstmtp->add(" + \" \" + ");
        cstmtp->add(iterateSubtreeReturnEdits(elemp));
        cstmtp->add(" + \")\";\n");
        AstCExpr* const cexprp = new AstCExpr{fl};
        cexprp->dtypeSetString();
        const bool handleElem = VN_IS(selp->dtypep()->skipRefp(), ClassRefDType);
        AstNodeExpr* defaultp;  // Value of an element that does not exist
        if (assocDtp && !handleElem) {
            // exprp with the element selp replaced by the default element
            defaultp = exprp->cloneTreePure(false);
            AstNode* const defaultSelp = selp->clonep();
            AstCExpr* const atDefaultp = new AstCExpr{fl};
            atDefaultp->add(arrayp->cloneTreePure(false));
            atDefaultp->add(".atDefault()");
            atDefaultp->dtypeFrom(selp);
            if (defaultSelp == defaultp) {
                defaultp = atDefaultp;
            } else {
                defaultSelp->replaceWith(atDefaultp);
            }
            VL_DO_DANGLING(defaultSelp->deleteTree(), defaultSelp);
        } else {
            defaultp = new AstConst{fl, AstConst::WidthedValue{}, width, 0};
        }
        cexprp->add("([&]{\nstd::string ret = \"((as const (Array (_ BitVec " + cvtToStr(idxWidth)
                    + ") (_ BitVec " + cvtToStr(width) + "))) \" + ");
        cexprp->add(getConstFormat(defaultp));
        cexprp->add(" + \")\";\n");
        AstNode* bodyp = cstmtp;
        if (nonNullp) bodyp = new AstIf{fl, nonNullp, cstmtp};
        cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                                 new AstForeach{fl, headerp, bodyp}, true});
        cexprp->add("return ret;\n})()");
        return new AstSFormatF{fl, "%s", false, cexprp};
    }
    // SMT constant with the current value of a variable, an SMT array for an array
    AstNodeExpr* newStateFormatp(AstNodeExpr* varExprp) {
        // A rand_mode(0) array selected by a random index needs all of its elements
        const AstNodeDType* const dtypep = varExprp->dtypep()->skipRefp();
        if (!dtypep->isNonPackedArray() || !dtypep->subDTypep()->skipRefp()->isIntegralOrPacked())
            return getConstFormat(varExprp);
        varExprp->user1(false);  // Read the elements as state
        // newIndexedArrayp replaces the index by each element's
        AstNodeExpr* const selp
            = newSel(varExprp->fileline(), varExprp, new AstConst{varExprp->fileline(), 0});
        AstSFormatF* const arrayp = newIndexedArrayp(selp, selp);
        // varExprp may be the visited reference, which a global constraint keeps for later
        VL_DO_DANGLING(pushDeletep(selp), selp);
        return arrayp;
    }
    // Replace an expression reading a non-random array through a random index
    bool editStateArraySel(AstNodeExpr* nodep) {
        if (!nodep->dtypep()->skipRefp()->isIntegralOrPacked()) return false;
        AstNodeExpr* const selp = randIndexSelp(nodep, isRandIndex);
        if (!selp) return false;
        AstSFormatF* const arrayp = newIndexedArrayp(nodep, selp);
        const int sortWidth = smtIndexWidth(selp);
        AstNodeExpr* const indexp = selIndexp(selp)->unlinkFrBack();
        // The offset into a fixed-size array is unsigned, even when computed as signed
        AstNodeExpr* const smtIndexp
            = newSmtIndexp(indexp, VN_IS(selp, CMethodHard) && indexp->isSigned(), sortWidth);
        nodep->replaceWith(createSolverArrDerefp(
            nodep->fileline(), arrayp, VN_AS(iterateSubtreeReturnEdits(smtIndexp), NodeExpr)));
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        return true;
    }
    // Report a random index into a non-random array not read as an integral value
    void unsupportedStateArraySel(AstNodeExpr* selp) {
        selp->v3warn(E_UNSUPPORTED, "Unsupported: Randomized index into a non-random array "
                                    "selecting a non-integral value");
        selp->user1(false);
        editFormat(selp);
    }

    // Add registration regp of a variable reached through member objects
    void addMemberselRegistration(AstNode* regp, AstVar* const varp,
                                  AstMemberSel* const memberselp, const std::string& smtName,
                                  const RandomizeMode& randMode, AstBegin* const initp) {
        // Not written back while the variable's own rand_mode (if randMode.usesMode) or a
        // handle on the path to it is off. Not registered through a null handle (IEEE
        // 1800-2023 18.4), and a registration made before is removed, as its object may be
        // gone.
        FileLine* const fl = varp->fileline();
        const auto newGenCallp = [&](VCMethod method) {
            AstCMethodHard* const callp = new AstCMethodHard{
                fl,
                new AstVarRef{fl, VN_AS(m_genp->user2p(), NodeModule), m_genp, VAccess::READWRITE},
                method};
            callp->dtypeSetVoid();
            AstNodeExpr* const namep = m_nestedAccessp
                                           ? m_nestedAccessp->cloneName()
                                           : new AstSFormatF{fl, smtName, false, nullptr};
            callp->addPinsp(namep);
            return callp->makeStmt();
        };
        AstNodeExpr* activep = newHandlesActivep(m_memberMap, memberselp->fromp(), true, false);
        AstVar* const subRandModeVarp = getRandModeVarFromClass(VN_AS(varp->user2p(), NodeModule));
        if (randMode.usesMode && subRandModeVarp) {
            AstMemberSel* const randModeSelp
                = new AstMemberSel{fl, memberselp->fromp()->cloneTree(false), subRandModeVarp};
            randModeSelp->dtypep(subRandModeVarp->dtypep());
            AstCMethodHard* const leafAtp = new AstCMethodHard{
                fl, randModeSelp, VCMethod::ARRAY_AT, new AstConst{fl, randMode.index}};
            leafAtp->dtypeSetUInt32();
            activep = activep ? new AstLogAnd{fl, activep, leafAtp}
                              : static_cast<AstNodeExpr*>(leafAtp);
        }
        if (activep) {
            regp->addNext(new AstIf{fl, activep,
                                    newGenCallp(VCMethod::RANDOMIZER_CLEAR_VAR_DISABLED),
                                    newGenCallp(VCMethod::RANDOMIZER_SET_VAR_DISABLED)});
        }
        if (AstNodeExpr* const nonNullp
            = newHandlesActivep(m_memberMap, memberselp->fromp(), false, true)) {
            regp = new AstIf{fl, nonNullp, regp, newGenCallp(VCMethod::RANDOMIZER_CLEAR_VAR)};
        }
        addRegistrationStmt(regp, initp);
    }

    void markRandc(AstVar* const varp, const std::string& smtName, AstBegin* const initp) {
        // The randomizer records the used values of a randc variable as 64-bit numbers
        const int width = arrayElementDTypep(varp->dtypep())->width();
        if (width > VL_QUADSIZE) {
            varp->v3warn(E_UNSUPPORTED, "Unsupported: Constrained randc variable "
                                            << varp->prettyNameQ() << " is " << width
                                            << " bits, wider than the implemented " << VL_QUADSIZE
                                            << " bits (IEEE 1800-2023 18.4.2).");
            return;
        }
        AstCMethodHard* const markp = new AstCMethodHard{
            varp->fileline(),
            new AstVarRef{varp->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                          VAccess::READWRITE},
            VCMethod::RANDOMIZER_MARK_RANDC};
        markp->dtypeSetVoid();
        AstNodeExpr* const nameExprp
            = m_nestedAccessp ? m_nestedAccessp->cloneName()
                              : new AstSFormatF{varp->fileline(), smtName, false, nullptr};
        markp->addPinsp(nameExprp);
        addRegistrationStmt(markp->makeStmt(), initp);
    }

    AstNodeModule* getLeftmostVarModulep(AstMemberSel* const memberselp,
                                         AstVar* const varp) const {
        if (memberselp) {
            // For memberselp, find the leftmost varref to get the class
            AstNode* leftMostNodep = memberselp->fromp();
            while (AstMemberSel* const nestedMemberSelp = VN_CAST(leftMostNodep, MemberSel)) {
                leftMostNodep = nestedMemberSelp->fromp();
            }
            if (AstNodeVarRef* const rootVarRefp = VN_CAST(leftMostNodep, NodeVarRef)) {
                return VN_AS(rootVarRefp->varp()->user2p(), NodeModule);
            }
            return VN_AS(memberselp->user2p(), NodeModule);
        }
        return VN_AS(varp->user2p(), NodeModule);
    }

    AstBegin* getInitp(AstVar* const varp, const bool memberselOrStructSel,
                       AstNodeModule* const classp) const {
        if (m_inlineInitBlockp) return m_inlineInitBlockp;
        varp->user3(true);
        if (memberselOrStructSel) {
            // Not in new(), as the selected object may not exist yet. In the setup of the
            // constraint, as every class solving the constraint runs it.
            UASSERT_OBJ(m_memberselInitTaskp, varp, "No setup task for the constraint");
            return newInitBlockp(m_memberselInitTaskp);
        } else {
            AstNodeFTask* const taskp = VN_AS(m_memberMap.findMember(classp, "new"), NodeFTask);
            UASSERT_OBJ(taskp, classp, "No new() in class");
            return newInitBlockp(taskp);
        }
        return nullptr;
    }

    void createWriteVarForClassFields(AstClass* const elemClassp, const std::string& smtName,
                                      AstVar* const iterVarp, const bool isUnpackedClassRefArray,
                                      AstNodeExpr* const arrayRefp, AstIf* const ifNonNullp,
                                      AstClassRefDType* elemClassRefDtp,
                                      AstNodeExpr* const activep) const {
        FileLine* const fl = arrayRefp->fileline();
        const std::string idxFmt
            = isUnpackedClassRefArray ? "%0x" : keyHexFormat(iterVarp->dtypep()->skipRefp());
        AstNode* enablesp = nullptr;  // While activep, written back
        AstNode* disablesp = nullptr;  // Otherwise not

        foreachSolverElemField(elemClassp, [&](AstVar* const memberVarp) {
            const int memberWidth = memberVarp->dtypep()->skipRefp()->width();

            AstNodeExpr* const arrayWrRefp = arrayRefp->cloneTree(false);
            if (AstVarRef* const varRefp = VN_CAST(arrayWrRefp, VarRef)) {
                varRefp->access(VAccess::WRITE);
            } else {
                VN_AS(arrayWrRefp, MemberSel)->access(VAccess::WRITE);
            }
            AstNodeExpr* atWritep;
            if (isUnpackedClassRefArray) {
                atWritep
                    = new AstArraySel{fl, arrayWrRefp, new AstVarRef{fl, iterVarp, VAccess::READ}};
            } else {
                atWritep = new AstCMethodHard{fl, arrayWrRefp, VCMethod::ARRAY_AT_WRITE,
                                              new AstVarRef{fl, iterVarp, VAccess::READ}};
            }
            atWritep->dtypep(elemClassRefDtp);
            AstMemberSel* const memberSelp = new AstMemberSel{fl, atWritep, memberVarp};

            AstCMethodHard* const writeVarp = new AstCMethodHard{
                fl,
                new AstVarRef{fl, VN_AS(m_genp->user2p(), NodeModule), m_genp, VAccess::READWRITE},
                VCMethod::RANDOMIZER_WRITE_VAR};
            writeVarp->dtypeSetVoid();
            writeVarp->addPinsp(memberSelp);
            writeVarp->addPinsp(
                new AstConst{fl, AstConst::Unsized64{}, static_cast<uint64_t>(memberWidth)});
            AstSFormatF* const namep
                = new AstSFormatF{fl, smtName + "." + idxFmt + "." + memberVarp->name(), false,
                                  new AstVarRef{fl, iterVarp, VAccess::READ}};
            if (activep) {
                AstCMethodHard* const enablep = new AstCMethodHard{
                    fl, writeVarp->fromp()->cloneTree(false),
                    VCMethod::RANDOMIZER_CLEAR_VAR_DISABLED, namep->cloneTree(false)};
                enablep->dtypeSetVoid();
                AstCMethodHard* const disablep = enablep->cloneTree(false);
                disablep->method(VCMethod::RANDOMIZER_SET_VAR_DISABLED);
                enablesp = AstNode::addNext(enablesp, enablep->makeStmt());
                disablesp = AstNode::addNext(disablesp, disablep->makeStmt());
            }
            writeVarp->addPinsp(namep);
            writeVarp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 0ULL});
            ifNonNullp->addThensp(writeVarp->makeStmt());
        });
        // The fields of the objects of an inactive array are not written back
        if (enablesp) {
            ifNonNullp->addThensp(new AstIf{fl, activep->cloneTree(false), enablesp, disablesp});
        }
    }

    void createSolverArrayHandle(AstVar* const varp, AstClassRefDType* elemClassRefDtp,
                                 AstNodeExpr* const arrayRefp, const bool isUnpackedClassRefArray,
                                 const std::string& smtName) const {
        // arrayRefp is the array of this or of a member object, consumed
        FileLine* const fl = varp->fileline();
        AstClass* const elemClassp = elemClassRefDtp->classp();

        AstVar* const iterVarp = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__Vi"),
                                            varp->findUInt32DType()};
        iterVarp->funcLocal(true);
        iterVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        // Associative array elements are reached by key, walked with first()/next()
        AstAssocArrayDType* const assocDtp = VN_CAST(varp->dtypep()->skipRefp(), AssocArrayDType);
        AstVar* const idxVarp = assocDtp
                                    ? new AstVar{fl, VVarType::BLOCKTEMP,
                                                 m_uniqueNames.get("__Vk"), assocDtp->keyDTypep()}
                                    : iterVarp;

        // Registered at each randomize(), as the array may hold other objects, after its
        // previous registration is cleared
        AstCMethodHard* const clearp = new AstCMethodHard{
            fl, new AstVarRef{fl, VN_AS(m_genp->user2p(), NodeModule), m_genp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_CLEAR_ELEM_VARS,
            new AstCExpr{fl, AstCExpr::Pure{}, "\"" + smtName + "\""}};
        clearp->dtypeSetVoid();
        AstNode* stmtsp
            = new AstAssign{fl, new AstVarRef{fl, iterVarp, VAccess::WRITE}, new AstConst{fl, 0}};

        AstNodeExpr* sizep;
        if (isUnpackedClassRefArray) {
            const int arraySize
                = VN_AS(varp->dtypep()->skipRefp(), UnpackArrayDType)->elementsConst();
            sizep = new AstConst{fl, static_cast<uint32_t>(arraySize)};
        } else {
            AstCMethodHard* const dynSizep
                = new AstCMethodHard{fl, arrayRefp->cloneTree(false), VCMethod::DYN_SIZE, nullptr};
            dynSizep->dtypeSetUInt32();
            sizep = dynSizep;
        }

        AstLoop* const loopp = new AstLoop{fl};
        stmtsp->addNext(loopp);
        loopp->addStmtsp(new AstLoopTest{
            fl, loopp, new AstLt{fl, new AstVarRef{fl, iterVarp, VAccess::READ}, sizep}});

        AstNodeExpr* const arrayReadRefp = arrayRefp->cloneTree(false);
        AstNodeExpr* atReadp;
        if (isUnpackedClassRefArray) {
            atReadp
                = new AstArraySel{fl, arrayReadRefp, new AstVarRef{fl, idxVarp, VAccess::READ}};
        } else {
            atReadp = new AstCMethodHard{fl, arrayReadRefp, VCMethod::ARRAY_AT,
                                         new AstVarRef{fl, idxVarp, VAccess::READ}};
        }
        atReadp->dtypep(elemClassRefDtp);
        AstIf* const ifNonNullp
            = new AstIf{fl, new AstNeq{fl, atReadp, new AstConst{fl, AstConst::Null{}}}, nullptr};
        loopp->addStmtsp(ifNonNullp);

        AstNodeExpr* const activep = newHandlesActivep(m_memberMap, arrayReadRefp, true, false);
        createWriteVarForClassFields(elemClassp, smtName, idxVarp, isUnpackedClassRefArray,
                                     arrayRefp, ifNonNullp, elemClassRefDtp, activep);
        if (activep) VL_DO_DANGLING(activep->deleteTree(), activep);

        loopp->addStmtsp(new AstAssign{
            fl, new AstVarRef{fl, iterVarp, VAccess::WRITE},
            new AstAdd{fl, new AstConst{fl, 1}, new AstVarRef{fl, iterVarp, VAccess::READ}}});

        // Not basic-randomized, unless the array is of a member object, which may also be
        // randomized on its own
        if (VN_IS(arrayRefp, VarRef)) varp->user3(true);
        // Not through a null member object
        AstNodeExpr* const nonNullp = newHandlesActivep(m_memberMap, arrayRefp, false, true);
        VL_DO_DANGLING(arrayRefp->deleteTree(), arrayRefp);
        AstBegin* initp = m_inlineInitBlockp;
        if (!initp) {
            UASSERT_OBJ(m_memberselInitTaskp, varp, "No randomize() to register array in");
            initp = newInitBlockp(m_memberselInitTaskp);
        }
        // At the beginning, so declared before referenced
        initp->addDeclsp(iterVarp);
        if (assocDtp) {
            idxVarp->funcLocal(true);
            initp->addDeclsp(idxVarp);
            AstCMethodHard* const firstp
                = new AstCMethodHard{fl, arrayReadRefp->cloneTree(false), VCMethod::ASSOC_FIRST,
                                     new AstVarRef{fl, idxVarp, VAccess::READWRITE}};
            firstp->dtypeSetInt();
            AstCMethodHard* const nextp = firstp->cloneTree(false);
            nextp->method(VCMethod::ASSOC_NEXT);
            AstNode* const firstStmtp = firstp->makeStmt();
            stmtsp = AstNode::addNext(firstStmtp, stmtsp);
            loopp->addStmtsp(nextp->makeStmt());
        }
        initp->addStmtsp(clearp->makeStmt());
        initp->addStmtsp(nonNullp ? new AstIf{fl, nonNullp, stmtsp} : stmtsp);
    }

    void createSolverVarHandle(AstVar* const varp, const bool structSelOrCMeth,
                               const bool isGlobalConstrained, const RandomizeMode randMode,
                               AstMemberSel* const memberselp, const std::string& smtName,
                               AstNodeModule* const classOrPackagep, AstNodeModule* const classp,
                               AstBegin* const initp) {
        uint32_t unpackedDims = 0;
        if (varp->dtypeSkipRefp()->isNonPackedArray()) {
            unpackedDims = varp->dtypep()->dimensions(false).second;
        }
        if (VN_IS(varp->dtypeSkipRefp(), StructDType)
            && !VN_AS(varp->dtypeSkipRefp(), StructDType)->packed()) {
            markStructConstrainedRandRecurse(varp->dtypeSkipRefp());
            unpackedDims = 1;
        }
        AstCMethodHard* const methodp = new AstCMethodHard{
            varp->fileline(),
            new AstVarRef{varp->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                          VAccess::READWRITE},
            VCMethod::RANDOMIZER_WRITE_VAR};
        methodp->dtypeSetVoid();
        if (memberselp) {
            methodp->addPinsp(memberselp);
        } else {
            AstVarRef* const varRefp
                = new AstVarRef{varp->fileline(), classp, varp, VAccess::WRITE};
            varRefp->classOrPackagep(classOrPackagep);
            methodp->addPinsp(varRefp);
        }
        const size_t width = arrayElementDTypep(varp->dtypep())->width();
        methodp->addPinsp(new AstConst{varp->fileline(), AstConst::Unsized64{}, width});
        AstNodeExpr* const varnamep = new AstCExpr{varp->fileline(), AstCExpr::Pure{},
                                                   "\"" + smtName + "\"", varp->width()};
        varnamep->dtypep(varp->dtypep());
        methodp->addPinsp(varnamep);
        methodp->addPinsp(
            new AstConst{varp->dtypep()->fileline(), AstConst::Unsized64{}, unpackedDims});
        if (randMode.usesMode && !(isGlobalConstrained && memberselp)) {
            methodp->addPinsp(
                new AstConst{varp->fileline(), AstConst::Unsized64{}, randMode.index});
        }
        // For globalConstrained sub-object members with rand_mode:
        // Always call write_var (keeps variable in solver for constraint
        // evaluation), but toggle disabled state so the solver skips
        // write-back when rand_mode is off.
        if (memberselp) {
            addMemberselRegistration(methodp->makeStmt(), varp, memberselp, smtName,
                                     isGlobalConstrained ? randMode : RandomizeMode{}, initp);
        } else {
            initp->addStmtsp(methodp->makeStmt());
        }
        if (varp->lifetime().isStatic() && randMode.usesMode) {
            AstCMethodHard* const markp = new AstCMethodHard{
                varp->fileline(),
                new AstVarRef{varp->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                              VAccess::READWRITE},
                VCMethod::RANDOMIZER_MARK_VAR_STATIC};
            AstNodeExpr* const namep = new AstCExpr{varp->fileline(), AstCExpr::Pure{},
                                                    "\"" + smtName + "\"", varp->width()};
            namep->dtypep(varp->dtypep());
            markp->addPinsp(namep);
            markp->dtypeSetVoid();
            initp->addStmtsp(markp->makeStmt());
        }
        // If randc, also emit markRandc() for cyclic tracking
        if (varp->isRandC()) markRandc(varp, smtName, initp);
    }

    AstNodeExpr* createVarExprp(AstNodeVarRef* nodep, const RandomizeMode randMode,
                                const std::string& smtName, const bool isGlobalConstrained,
                                AstMemberSel* memberselp, AstVar* const varp) {
        // Use AstSFormatF (not AstConst{String}) to prevent editFormat/V3Const
        // from reformatting the SMT variable name into a hex literal
        AstNodeExpr* exprp = new AstSFormatF{
            nodep->fileline(), m_nestedAccessp ? nodep->name() : smtName, false, nullptr};
        // A variable of the object of an inactive handle is a state variable. The objects of
        // a handle array are checked where their fields are selected.
        // rand_mode() only affects rand variables, so not the size variable of an array of
        // the object, which is pinned instead.
        const bool classHandleArray = isClassHandleArray(varp);
        AstNodeExpr* const handlesActivep
            = memberselp && !classHandleArray && varp->rand().isRandomizable()
                  ? newHandlesActivep(m_memberMap, memberselp->fromp(), true, false)
                  : nullptr;
        if ((!randMode.usesMode || classHandleArray) && !handlesActivep) {
            // Global constraints keep nodep alive for write_var processing
            if (!isGlobalConstrained) VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return exprp;
        }

        // Get const format, using memberselp if available for correct width/value
        AstNodeExpr* constFormatp = newStateFormatp(memberselp ? memberselp->cloneTree(false)
                                                               : static_cast<AstNodeExpr*>(nodep));
        if (!randMode.usesMode) {
            exprp = new AstCond{varp->fileline(), handlesActivep, exprp, constFormatp};
            exprp->user1(true);  // Mark as formatted
            return exprp;
        }

        // Static rand vars route through the var's owning class's static array
        // (may differ from m_classp when the rand var lives in a sub-object).
        AstNodeExpr* randModeAccessp;
        const bool varIsStatic = varp->lifetime().isStatic();
        AstClass* const varOwningClassp = varIsStatic ? VN_CAST(varp->user2p(), Class) : nullptr;
        AstVar* const ownerStaticRandModeVarp
            = varOwningClassp ? findStaticRandModeVar(m_memberMap, varOwningClassp) : nullptr;
        if (ownerStaticRandModeVarp) {
            randModeAccessp = new AstVarRef{varp->fileline(),
                                            VN_AS(ownerStaticRandModeVarp->user2p(), NodeModule),
                                            ownerStaticRandModeVarp, VAccess::READ};
        } else if (memberselp) {
            AstNodeModule* const varClassp = VN_AS(varp->user2p(), NodeModule);
            AstVar* const effectiveRandModeVarp = getRandModeVarFromClass(varClassp);
            if (effectiveRandModeVarp) {
                // Member's class has randmode, use it
                AstNodeExpr* parentAccessp = memberselp->fromp()->cloneTree(false);
                AstMemberSel* randModeSelp
                    = new AstMemberSel{varp->fileline(), parentAccessp, effectiveRandModeVarp};
                randModeSelp->dtypep(effectiveRandModeVarp->dtypep());
                randModeAccessp = randModeSelp;
            } else {
                // Member's class has no randmode, use current scope's randmode
                UASSERT_OBJ(m_randModeVarp, nodep, "No m_randModeVarp");
                randModeAccessp
                    = new AstVarRef{varp->fileline(), VN_AS(m_randModeVarp->user2p(), NodeModule),
                                    m_randModeVarp, VAccess::READ};
            }
        } else {
            UASSERT_OBJ(m_randModeVarp, nodep, "No m_randModeVarp");
            randModeAccessp
                = new AstVarRef{varp->fileline(), VN_AS(m_randModeVarp->user2p(), NodeModule),
                                m_randModeVarp, VAccess::READ};
        }

        AstCMethodHard* const atp
            = new AstCMethodHard{nodep->fileline(), randModeAccessp, VCMethod::ARRAY_AT,
                                 new AstConst{nodep->fileline(), randMode.index}};
        atp->dtypeSetUInt32();
        AstNodeExpr* const condp = handlesActivep
                                       ? new AstLogAnd{varp->fileline(), atp, handlesActivep}
                                       : static_cast<AstNodeExpr*>(atp);
        exprp = new AstCond{varp->fileline(), condp, exprp, constFormatp};
        exprp->user1(true);  // Mark as formatted
        return exprp;
    }

    // Whether selp is the member select of a variable captured by captureRefByThis()
    static bool isCapturedThisSel(const AstMemberSel* selp) {
        return VN_IS(selp->fromp(), VarRef)
               && selp->fromp()->user1()  // Depending on a randomized variable
               && selp->user2p()  // Pointer to containing module
               && VN_AS(selp->user2p(), NodeModule) == selp->varp()->user2p();
    }

    // VISITORS
    void visit(AstNodeVarRef* nodep) override {
        AstVar* varp = nodep->varp();
        if (varp->user4p()) {
            bool isSizeRef = false;
            if (AstCMethodHard* const methodp = VN_CAST(nodep->backp(), CMethodHard)) {
                if (methodp->method() == VCMethod::DYN_SIZE) isSizeRef = true;
            }
            if (!isSizeRef && m_sizeConstrainedArraysp) { m_sizeConstrainedArraysp->insert(varp); }
        }

        // Check if this variable is marked as globally constrained
        const bool isGlobalConstrained = nodep->varp()->globalConstrained();

        AstMemberSel* memberselp = nullptr;
        bool structSelOrCMeth = false;
        // Set below only when narrowing to one struct field/array element;
        // staying null means "check varp's own type" (see its use further down).
        AstNodeDType* selectedDtypep = nullptr;
        std::string smtName;
        if (m_nestedAccessp) {
            m_nestedAccessp->addVarNamePart(
                new AstSFormatF{varp->fileline(), nodep->name(), false, nullptr}, nodep->name());
            smtName = m_nestedAccessp->smtName();
            memberselp = m_nestedAccessp->accessTree();
        } else if (VN_IS(nodep->backp(), MemberSel)) {
            // Build complete path from topmost MemberSel
            AstNode* topMemberSelp = nodep->backp();
            while (VN_IS(topMemberSelp->backp(), MemberSel)) {
                topMemberSelp = topMemberSelp->backp();
            }
            memberselp = VN_AS(topMemberSelp, MemberSel)->cloneTree(false);
            smtName = buildMemberPath(memberselp);
        } else if (VN_IS(nodep->backp(), StructSel) || VN_IS(nodep->backp(), CMethodHard)) {
            // Build complete path for topmost StructSel or CMethodHard::ARRAY_AT
            AstNode* topNodep = nodep->backp();
            while (VN_IS(topNodep->backp(), StructSel) || VN_IS(topNodep->backp(), CMethodHard)) {
                topNodep = topNodep->backp();
            }

            if (VN_IS(topNodep, StructSel) || VN_IS(topNodep, CMethodHard)) {
                structSelOrCMeth = true;
                selectedDtypep = VN_AS(topNodep, NodeExpr)->dtypep();
            }

            memberselp = VN_CAST(topNodep, MemberSel);
            if (memberselp) smtName = buildMemberPath(memberselp);

            // Above functions returned empty string, unrecognized node type,
            // Using nodep->name();
            if (smtName == "") smtName = nodep->name();
        } else {
            // No MemberSel, StructSel or CMethodHard:at : just variable name
            smtName = nodep->name();
        }
        // Recorded so the runtime can tell constraints naming only randc variables apart
        // (#8058). A name matching no registered variable, as a nested access path formatted
        // at runtime does, must be taken as a non-randc variable, so its constraint is never
        // randc-only.
        UASSERT_OBJ(m_constraintVarsp, nodep,
                    "Variable reference outside a constraint expression");
        if (nodep->user1()) m_constraintVarsp->insert(smtName);

        if (memberselp) varp = memberselp->varp();
        // The SMT translation assumes bit-vector operands and does not
        // type-check; embedding a real value produces a malformed width.
        // Check the selected field/element's type, not the whole
        // struct/array's -- a real sibling field elsewhere is irrelevant.
        if (dtypeContainsReal(structSelOrCMeth ? selectedDtypep : varp->dtypep())) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: real value in this constraint expression");
            return;
        }
        AstNodeModule* const classOrPackagep = nodep->classOrPackagep();
        const RandomizeMode randMode = {.asUQuad = varp->user1()};
        if (!randMode.usesMode && editFormat(nodep)) return;
        (m_inFuncArg ? m_funcArgNames : m_itemVarNames).insert(smtName);

        VNRelinker relinker;
        nodep->unlinkFrBack(&relinker);
        AstNodeExpr* const exprp
            = createVarExprp(nodep, randMode, smtName, isGlobalConstrained, memberselp, varp);
        relinker.relink(exprp);

        bool isClassRefArray = false;
        bool isUnpackedClassRefArray = false;
        AstClassRefDType* elemClassRefDtp = nullptr;
        {
            AstNodeDType* varDtp = varp->dtypep()->skipRefp();
            if (varDtp->isNonPackedArray()) {
                AstNodeDType* const elemDtp = varDtp->subDTypep()->skipRefp();
                elemClassRefDtp = VN_CAST(elemDtp, ClassRefDType);
                if (elemClassRefDtp) {
                    isClassRefArray = true;
                    isUnpackedClassRefArray = VN_IS(varDtp, UnpackArrayDType);
                }
            }
        }

        // Global / inline / class-level member-select refs key on the full path
        // (so same-type sub-objects c1.x, c2.x stay distinct); a plain class-level
        // variable keys on user3(). Inline 'with' dedups per function (own solver).
        // The objects of a handle array are registered by each class's randomize().
        const bool perClass = isGlobalConstrained || memberselp || isClassRefArray;
        const bool alreadyWritten = m_inlineInitBlockp ? m_inlineWrittenVars.count(smtName) > 0
                                    : perClass         ? m_writtenVars.count(smtName) > 0
                                                       : !m_newWrittenVarsp->insert(varp).second;
        const bool shouldWriteVar = !alreadyWritten;
        if (shouldWriteVar) {
            // Track this variable path as written
            if (m_inlineInitBlockp)
                m_inlineWrittenVars.insert(smtName);
            else if (perClass)
                m_writtenVars.insert(smtName);
            // For global constraints, delete nodep after processing
            if (isGlobalConstrained && !nodep->backp()) VL_DO_DANGLING(pushDeletep(nodep), nodep);

            if (isClassRefArray && !m_nestedAccessp) {
                AstNodeExpr* arrayRefp = memberselp;
                if (!arrayRefp) {
                    AstVarRef* const varRefp = new AstVarRef{
                        varp->fileline(), VN_AS(varp->user2p(), NodeModule), varp, VAccess::READ};
                    varRefp->classOrPackagep(classOrPackagep);
                    arrayRefp = varRefp;
                }
                createSolverArrayHandle(varp, elemClassRefDtp, arrayRefp, isUnpackedClassRefArray,
                                        smtName);
                return;
            }
            AstNodeModule* const classp = getLeftmostVarModulep(memberselp, varp);
            const bool inRandomize = memberselp || structSelOrCMeth;
            AstBegin* const initp = getInitp(varp, inRandomize, classp);
            if (m_nestedAccessp) {
                AstStmtExpr* const writeVarStmtp = m_nestedAccessp->makeWriteVarStmt(varp, m_genp);
                addMemberselRegistration(writeVarStmtp, varp, memberselp, smtName,
                                         isGlobalConstrained ? randMode : RandomizeMode{}, initp);
                // If randc, also emit markRandc() for cyclic tracking
                if (varp->isRandC()) markRandc(varp, smtName, initp);
            } else if (isMultiDimHandleArray(varp->dtypep())) {
                exprp->v3warn(E_UNSUPPORTED, "Unsupported: Constraint referencing a"
                                             " multi-dimensional array of class handles");
            } else {
                createSolverVarHandle(varp, structSelOrCMeth, isGlobalConstrained, randMode,
                                      memberselp, smtName, classOrPackagep, classp, initp);
                AstNodeDType* dtp = varp->dtypep()->skipRefp();
                while (VN_IS(dtp, UnpackArrayDType)) dtp = dtp->subDTypep()->skipRefp();
                if (VN_IS(dtp, AssocArrayDType) && !inRandomize && !m_inlineInitBlockp) {
                    // Keys can be added to an associative array (also one in a fixed-size array)
                    // after new(), so randomize() registers it again for its current elements.
                    // new() still registers it for a randomize() of a base class, which does not
                    // run this one.
                    createSolverVarHandle(varp, false, isGlobalConstrained, randMode, nullptr,
                                          smtName, classOrPackagep, classp,
                                          getInitp(varp, true, classp));
                }
            }
        } else {
            // Variable already written, clean up cloned memberselp if any
            if (memberselp) VL_DO_DANGLING(memberselp->deleteTree(), memberselp);
            // Delete nodep if it's a global constraint (not deleted yet)
            if (isGlobalConstrained && !nodep->backp()) VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
        if (m_nestedAccessp) { VL_DO_DANGLING(delete m_nestedAccessp, m_nestedAccessp); }
    }
    // Build the number of set bits of argp (consumed) as a narrow sum
    AstNodeExpr* buildCountOnesExpansion(FileLine* fl, AstNodeExpr* argp) {
        // Sum the bits pairwise in a balanced tree, each adder only as wide as its sum.
        // A chain of full-width adds is very slow to solve: z3 takes a minute on a
        // 128-bit $countones(x) inside {...}, against milliseconds for the tree.
        std::vector<AstNodeExpr*> sums;
        sums.reserve(argp->width());
        for (int i = 0; i < argp->width(); ++i) {
            sums.push_back(new AstSel{fl, i ? argp->cloneTreePure(false) : argp, i, 1});
            sums.back()->user1(true);
        }
        while (sums.size() > 1) {
            std::vector<AstNodeExpr*> nextSums;
            for (size_t i = 0; i + 1 < sums.size(); i += 2) {
                const int width = std::max(sums[i]->width(), sums[i + 1]->width()) + 1;
                AstNodeExpr* const lhsp = new AstExtend{fl, sums[i], width};
                AstNodeExpr* const rhsp = new AstExtend{fl, sums[i + 1], width};
                AstNodeExpr* const addp = new AstAdd{fl, lhsp, rhsp};
                lhsp->user1(true);
                rhsp->user1(true);
                addp->user1(true);
                nextSums.push_back(addp);
            }
            if (sums.size() % 2) nextSums.push_back(sums.back());
            sums.swap(nextSums);
        }
        return sums[0];
    }

    void visit(AstCountOnes* nodep) override {
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        AstNodeExpr* sump = buildCountOnesExpansion(fl, argp);
        sump = adjustWidth(fl, sump, nodep->width(), nodep->dtypep()->numeric());
        sump->user1(true);
        nodep->replaceWith(sump);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(sump);
    }
    // Lower $countones(x) == 1 as $onehot(x), and $countones(x) <= 1 as $onehot0(x)
    bool editOneHotCount(AstNodeBiop* nodep) {
        // IEEE 1800-2023 20.9 defines them so. Their lowering is a few nodes, while the count
        // is a sum over every bit of x, which is large and slow to solve when x is wide.
        if (!nodep->user1()) return false;
        const bool eq = VN_IS(nodep, Eq);
        const bool lte = VN_IS(nodep, Lte) || VN_IS(nodep, LteS);
        const bool gte = VN_IS(nodep, Gte) || VN_IS(nodep, GteS);
        AstCountOnes* countp = (eq || lte) ? VN_CAST(nodep->lhsp(), CountOnes) : nullptr;
        const AstConst* constp = VN_CAST(nodep->rhsp(), Const);
        if (!countp && (eq || gte)) {
            countp = VN_CAST(nodep->rhsp(), CountOnes);
            constp = VN_CAST(nodep->lhsp(), Const);
        }
        if (!countp || !constp || !constp->num().isEqOne()) return false;
        FileLine* const flp = nodep->fileline();
        AstNodeExpr* const argp = countp->lhsp()->unlinkFrBack();
        AstNodeExpr* const newp
            = eq ? static_cast<AstNodeExpr*>(new AstOneHot{flp, argp}) : new AstOneHot0{flp, argp};
        newp->user1(true);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(newp);
        return true;
    }
    void visit(AstRedXor* nodep) override {
        if (editFormat(nodep)) return;

        // Build popcount expansion: (extract x 1 1) ^ (extract x 2 2) ^ ...
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();

        AstNodeExpr* redxorp = new AstSel{fl, argp, 0, 1};
        redxorp->user1(true);
        for (int i = 1; i < argp->width(); i++) {
            AstSel* const selp = new AstSel{fl, argp->cloneTreePure(false), i, 1};
            selp->user1(true);

            redxorp = new AstXor{fl, redxorp, selp};
            redxorp->user1(true);
        }

        nodep->replaceWith(redxorp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(redxorp);
    }
    void visit(AstRedAnd* nodep) override {
        if (editFormat(nodep)) return;
        // Convert to (~x == 0)
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const V3Number numZero{fl, argp->width(), 0};
        AstNodeExpr* const negp = new AstNot{fl, argp};
        negp->user1(true);
        AstNodeExpr* const eqp = new AstEq{fl, negp, new AstConst{fl, numZero}};
        eqp->user1(true);
        nodep->replaceWith(eqp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(eqp);
    }
    void visit(AstRedOr* nodep) override {
        if (editFormat(nodep)) return;
        // Convert to (x != 0)
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const V3Number numZero{fl, argp->width(), 0};
        AstNodeExpr* const neqp = new AstNeq{fl, argp, new AstConst{fl, numZero}};
        neqp->user1(true);
        nodep->replaceWith(neqp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(neqp);
    }
    void visit(AstOneHot* nodep) override {
        if (editFormat(nodep)) return;
        // $onehot(x) = (x != 0) && ((x & (x-1)) == 0)
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const int w = argp->width();

        const V3Number numZero{fl, w, 0};
        AstNeq* const neZerop
            = new AstNeq{fl, argp->cloneTreePure(false), new AstConst{fl, numZero}};
        neZerop->user1(true);

        const V3Number numOne{fl, w, 1};
        AstSub* const subp = new AstSub{fl, argp->cloneTreePure(false), new AstConst{fl, numOne}};
        subp->user1(true);

        AstAnd* const andp = new AstAnd{fl, argp, subp};
        andp->user1(true);

        const V3Number numZero2{fl, w, 0};
        AstEq* const eqZerop = new AstEq{fl, andp, new AstConst{fl, numZero2}};
        eqZerop->user1(true);

        AstLogAnd* const resultp = new AstLogAnd{fl, neZerop, eqZerop};
        resultp->user1(true);

        nodep->replaceWith(resultp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(resultp);
    }
    void visit(AstOneHot0* nodep) override {
        if (editFormat(nodep)) return;
        // $onehot0(x) = (x & (x-1)) == 0
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const int w = argp->width();

        const V3Number numOne{fl, w, 1};
        AstSub* const subp = new AstSub{fl, argp->cloneTreePure(false), new AstConst{fl, numOne}};
        subp->dtypeFrom(argp);
        subp->user1(true);

        AstAnd* const andp = new AstAnd{fl, argp, subp};
        andp->dtypeFrom(argp);
        andp->user1(true);

        const V3Number numZero{fl, w, 0};
        AstEq* const eqp = new AstEq{fl, andp, new AstConst{fl, numZero}};
        eqp->user1(true);

        nodep->replaceWith(eqp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(eqp);
    }
    void visit(AstCountBits* nodep) override {
        if (editFormat(nodep)) return;
        FileLine* const fl = nodep->fileline();

        bool countOnes = false;
        bool countZeros = false;
        for (AstNodeExpr* ctrlp : {nodep->rhsp(), nodep->thsp(), nodep->fhsp()}) {
            const AstConst* const cp = VN_CAST(ctrlp, Const);
            if (!cp) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: non-constant control in $countbits inside constraint");
                AstConst* const zerop
                    = new AstConst{fl, AstConst::WidthedValue{}, nodep->width(), 0U};
                nodep->replaceWith(zerop);
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
                return;
            }
            if (cp->num().bitIs1(0) && !countOnes)
                countOnes = true;
            else if (cp->num().bitIs0(0) && !countZeros)
                countZeros = true;
        }

        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const int argWidth = argp->width();
        AstNodeExpr* sump = nullptr;
        if (countOnes && countZeros) {
            // ones + zeros = width for 2-state types
            sump = new AstConst{fl, AstConst::WidthedValue{}, nodep->width(), (uint32_t)argWidth};
            VL_DO_DANGLING(argp->deleteTree(), argp);
        } else if (countOnes) {
            sump = buildCountOnesExpansion(fl, argp);
        } else if (countZeros) {
            // width - countones(x)
            AstNodeExpr* const onesCountp = buildCountOnesExpansion(fl, argp);
            const V3Number widthVal{nodep, onesCountp->width(), (uint32_t)argWidth};
            sump = new AstSub{fl, new AstConst{fl, widthVal}, onesCountp};
            sump->user1(true);
        } else {
            sump = new AstConst{fl, AstConst::WidthedValue{}, nodep->width(), 0U};
            VL_DO_DANGLING(argp->deleteTree(), argp);
        }

        sump = adjustWidth(fl, sump, nodep->width(), nodep->dtypep()->numeric());
        sump->user1(true);

        nodep->replaceWith(sump);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(sump);
    }
    void visit(AstCLog2* nodep) override {
        if (editFormat(nodep)) return;
        // $clog2(x): ITE chain (x<=1)?0 : (x<=2)?1 : ... : argWidth
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const argp = nodep->lhsp()->unlinkFrBack();
        const int argWidth = argp->width();
        const int resultWidth = nodep->width();

        AstNodeExpr* resultp
            = new AstConst{fl, AstConst::WidthedValue{}, resultWidth, (uint32_t)argWidth};

        for (int k = argWidth - 1; k >= 0; k--) {
            V3Number threshold{fl, argWidth, 0};
            if (k < 32)
                threshold.setLong(1ULL << k);
            else
                threshold.setBit(k, 1);

            AstLte* const ltep
                = new AstLte{fl, argp->cloneTreePure(false), new AstConst{fl, threshold}};
            ltep->user1(true);

            AstConst* const valuep
                = new AstConst{fl, AstConst::WidthedValue{}, resultWidth, (uint32_t)k};

            resultp = new AstCond{fl, ltep, valuep, resultp};
            resultp->dtypeChgSigned(VSigning::SIGNED);
            resultp->user1(true);
        }

        VL_DO_DANGLING(argp->deleteTree(), argp);
        nodep->replaceWith(resultp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        iterate(resultp);
    }
    void visit(AstIsUnbounded* nodep) override {
        // Only true for the literal '$' token, never a real expression, so
        // this always folds to false. It has no runtime implementation of
        // its own, so it must be substituted now rather than left for later.
        nodep->v3warn(CONSTRAINTIGN,
                      "Unsupported: $isunbounded() in a constraint, treating as constant");
        AstConst* const zerop = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
        nodep->replaceWith(zerop);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        // So the constant is rendered as an SMT literal like every other
        // folded constant here, instead of being left behind unconverted.
        iterate(zerop);
    }
    void handlePow(AstNodeBiop* nodep) {
        if (AstConst* const exponentp = VN_CAST(nodep->rhsp(), Const)) {
            FileLine* const fl = nodep->fileline();
            AstNodeExpr* const basep = nodep->lhsp();
            const V3Number numOne{nodep, basep->width(), 1};
            AstNodeExpr* powerp = new AstConst{fl, numOne};
            const bool baseSigned = VN_IS(nodep, PowSS) || VN_IS(nodep, PowSU);
            const int32_t exponent = baseSigned ? exponentp->toSInt() : exponentp->toUInt();
            if (exponent > 0) {
                for (int32_t i = 0; i < exponent; i++) {
                    if (baseSigned) {
                        powerp = new AstMulS{fl, powerp, basep->cloneTreePure(false)};
                    } else {
                        powerp = new AstMul{fl, powerp, basep->cloneTreePure(false)};
                    }
                    powerp->user1(true);
                }
            } else if (exponent < 0) {
                // Limit chain of divisions to max 2, because operations are on integers.
                // Two divisions are needed to preserve the sign.
                if (baseSigned) {
                    powerp = new AstDivS{fl, powerp, basep->cloneTreePure(false)};
                    powerp->user1(true);
                    powerp = new AstDivS{fl, powerp, basep->cloneTreePure(false)};
                    powerp->user1(true);
                } else {
                    powerp = new AstDiv{fl, powerp, basep->cloneTreePure(false)};
                    powerp->user1(true);
                }
            }
            nodep->replaceWith(powerp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            iterate(powerp);
        } else if (const AstConst* const basep = VN_CAST(nodep->lhsp(), Const)) {
            if (basep->num().toUInt() == 2) {
                // Non-constant exponent, base == 2: transform to shift-based SMT expression.
                // AstPow/AstPowSU (unsigned exponent): 2**n -> 1<<n
                // AstPowSS/AstPowUS (signed exponent): 2**n -> n>=0 ? 1<<n : 0
                // IEEE 1800-2023 ss11.4.3: integer base with negative exponent gives 0,
                // which ShiftL cannot represent; use SMT ite (AstCond -> bvsge + bvshl).
                FileLine* const fl = nodep->fileline();
                AstNodeExpr* const rhsp = nodep->rhsp()->unlinkFrBack();
                const int width = nodep->width();
                const bool rhsDependent = rhsp->user1();
                AstConst* const onep = new AstConst{fl, AstConst::WidthedValue{}, width, 1};
                AstShiftL* const shiftp = new AstShiftL{fl, onep, rhsp, width};
                shiftp->dtypeFrom(nodep);
                shiftp->user1(rhsDependent);
                AstNodeExpr* resultp = shiftp;
                if (VN_IS(nodep, PowSS) || VN_IS(nodep, PowUS)) {
                    // Signed exponent: guard 1<<n with n>=0 check
                    AstNodeExpr* const nClonep = rhsp->cloneTreePure(false);
                    nClonep->user1(rhsDependent);
                    AstConst* const zeroNp
                        = new AstConst{fl, AstConst::WidthedValue{}, rhsp->width(), 0};
                    AstGteS* const condp = new AstGteS{fl, nClonep, zeroNp};
                    condp->user1(rhsDependent);
                    AstConst* const zeroRp = new AstConst{fl, AstConst::WidthedValue{}, width, 0};
                    resultp = new AstCond{fl, condp, shiftp, zeroRp};
                    resultp->dtypeFrom(nodep);
                    resultp->user1(nodep->user1());
                }
                nodep->replaceWith(resultp);
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
                iterate(resultp);
            } else {
                nodep->v3warn(CONSTRAINTIGN,
                              "Unsupported: Power (**) expression with non-2 base in constraint");
            }
        } else {
            nodep->v3warn(
                CONSTRAINTIGN,
                "Unsupported: Power (**) expression with non-constant exponent in constraint");
        }
    }
    void visit(AstPow* nodep) override { handlePow(nodep); }
    void visit(AstPowSS* nodep) override { handlePow(nodep); }
    void visit(AstPowSU* nodep) override { handlePow(nodep); }
    void visit(AstPowUS* nodep) override { handlePow(nodep); }
    // SMT-LIB2 shift operations (bvshl/bvlshr/bvashr) require both operands
    // to have the same bitvector width. Extend the narrower operand, then
    // truncate the result if the value was widened. Never truncate the shift
    // amount, as large shifts must still shift out all of the original bits.
    void handleShift(AstNodeBiop* nodep) {
        if (editFormat(nodep)) return;
        const int lhsWidth = nodep->lhsp()->width();
        const int rhsWidth = nodep->rhsp()->width();
        if (rhsWidth < lhsWidth) {
            FileLine* const fl = nodep->fileline();
            AstNodeExpr* const rhsp = nodep->rhsp()->unlinkFrBack();
            AstExtend* const extendp = new AstExtend{fl, rhsp, lhsWidth};
            // Always visit the wrapper: a rand MemberSel can have user1 unset until its
            // own visitor translates it. Copying that flag would format the entire
            // extension from the pre-randomize value. Non-rand children are still
            // formatted as constants by their own visitors.
            extendp->user1(true);
            nodep->rhsp(extendp);
        } else if (rhsWidth > lhsWidth) {
            FileLine* const fl = nodep->fileline();
            AstNodeDType* const dtypep = nodep->dtypep();
            AstNodeExpr* const lhsp = nodep->lhsp()->unlinkFrBack();
            AstNodeExpr* const extendp
                = VN_IS(nodep, ShiftRS)
                      ? static_cast<AstNodeExpr*>(new AstExtendS{fl, lhsp, rhsWidth})
                      : static_cast<AstNodeExpr*>(new AstExtend{fl, lhsp, rhsWidth});
            // Likewise, visit the extension instead of prematurely formatting rand
            // member selections as constants.
            extendp->user1(true);
            nodep->lhsp(extendp);
            nodep->dtypeSetLogicSized(rhsWidth, dtypep->numeric());
            VNRelinker relinker;
            nodep->unlinkFrBack(&relinker);
            AstSel* const selp = new AstSel{fl, nodep, 0, lhsWidth};
            selp->dtypep(dtypep);
            selp->user1(nodep->user1());
            relinker.relink(selp);
            iterate(selp);
            return;
        }
        editSMT(nodep, nodep->lhsp(), nodep->rhsp());
    }
    void visit(AstShiftL* nodep) override { handleShift(nodep); }
    void visit(AstShiftR* nodep) override { handleShift(nodep); }
    void visit(AstShiftRS* nodep) override { handleShift(nodep); }
    void visit(AstNodeBiop* nodep) override {
        if (editOneHotCount(nodep)) return;
        if (editFormat(nodep)) return;
        editSMT(nodep, nodep->lhsp(), nodep->rhsp());
    }
    void visit(AstNodeUniop* nodep) override {
        if (editFormat(nodep)) return;
        editSMT(nodep, nodep->lhsp());
    }
    void visit(AstNodeTriop* nodep) override {
        if (editFormat(nodep)) return;
        editSMT(nodep, nodep->lhsp(), nodep->rhsp(), nodep->thsp());
    }
    // State proofs of TRUE/FALSE/ERROR, all absent only when the predicate is RANDOM.
    struct GuardResult final {
        AstNodeExpr* truep;
        AstNodeExpr* falsep;
        AstNodeExpr* errorp;
    };
    AstVar* newGuardVarp(FileLine* const fl, AstBegin* const blockp, AstNodeDType* const dtypep) {
        AstVar* const varp
            = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__Vguard"), dtypep};
        varp->funcLocal(true);
        // Preserve the single stored branch/proof representation through later substitution.
        varp->noSubst(true);
        blockp->addStmtsp(varp);
        return varp;
    }
    static AstVarRef* newGuardRefp(AstVar* const varp, const VAccess access = VAccess::READ) {
        return new AstVarRef{varp->fileline(), varp, access};
    }
    struct GuardRead final {
        bool unresolved = false;  // Receiver value depends on an unsolved index/call
        bool sampled = false;  // Statements were emitted using the error status
        bool checked = false;  // A nullable receiver was checked
    };
    static AstNodeExpr* newNoGuardErrorp(AstVar* const errorVarp) {
        return new AstLogNot{errorVarp->fileline(), newGuardRefp(errorVarp)};
    }
    // Move receivers out of one cloned leaf in postorder. Every prefix is sampled once;
    // neither prefix scans nor cloning a prefix at every member selection are necessary.
    GuardRead editGuardReceivers(AstNode* const nodep, AstBegin* const blockp,
                                 AstVar* const errorVarp) {
        FileLine* const fl = nodep->fileline();
        if (AstCond* const condp = VN_CAST(nodep, Cond)) {
            const bool stateCond = !condp->condp()->user1();
            const bool stateValue = !condp->user1();
            GuardRead result = editGuardReceivers(condp->condp(), blockp, errorVarp);
            if (!stateCond) {
                result.unresolved = true;
                return result;
            }
            AstBegin* const thenBlockp
                = new AstBegin{fl, m_uniqueNames.get("__VguardThen"), nullptr, true};
            AstBegin* const elseBlockp
                = new AstBegin{fl, m_uniqueNames.get("__VguardElse"), nullptr, true};
            const GuardRead thenRead = editGuardReceivers(condp->thenp(), thenBlockp, errorVarp);
            const GuardRead elseRead = editGuardReceivers(condp->elsep(), elseBlockp, errorVarp);
            result.checked |= thenRead.checked || elseRead.checked;
            result.unresolved |= thenRead.unresolved || elseRead.unresolved;
            if (stateValue && !result.unresolved) {
                AstVar* const valueVarp = newGuardVarp(fl, blockp, condp->dtypep());
                thenBlockp->addStmtsp(
                    new AstIf{fl, newNoGuardErrorp(errorVarp),
                              new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE),
                                            condp->thenp()->unlinkFrBack()}});
                elseBlockp->addStmtsp(
                    new AstIf{fl, newNoGuardErrorp(errorVarp),
                              new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE),
                                            condp->elsep()->unlinkFrBack()}});
                blockp->addStmtsp(new AstIf{
                    fl, newNoGuardErrorp(errorVarp),
                    new AstIf{fl, condp->condp()->unlinkFrBack(), thenBlockp, elseBlockp}});
                condp->replaceWith(newGuardRefp(valueVarp));
                VL_DO_DANGLING(pushDeletep(condp), condp);
                result.sampled = true;
            } else if (thenRead.sampled || elseRead.sampled) {
                blockp->addStmtsp(new AstIf{
                    fl, newNoGuardErrorp(errorVarp),
                    new AstIf{fl, condp->condp()->cloneTree(false), thenBlockp, elseBlockp}});
                result.sampled = true;
            } else {
                VL_DO_DANGLING(thenBlockp->deleteTree(), thenBlockp);
                VL_DO_DANGLING(elseBlockp->deleteTree(), elseBlockp);
            }
            return result;
        }
        AstNodeExpr* fromp = nullptr;
        if (AstMemberSel* const selp = VN_CAST(nodep, MemberSel)) {
            fromp = selp->fromp();
        } else if (AstMethodCall* const callp = VN_CAST(nodep, MethodCall)) {
            fromp = callp->fromp();
        }
        bool fromUnresolved = false;
        GuardRead result;
        for (AstNode* const opp : {nodep->op1p(), nodep->op2p(), nodep->op3p(), nodep->op4p()}) {
            for (AstNode *childp = opp, *nextp; childp; childp = nextp) {
                nextp = childp->nextp();
                const GuardRead child = editGuardReceivers(childp, blockp, errorVarp);
                if (childp == fromp) fromUnresolved = child.unresolved;
                result.unresolved |= child.unresolved;
                result.sampled |= child.sampled;
                result.checked |= child.checked;
            }
        }
        // Propagate unsolved value dependencies once, not by rescanning each receiver prefix.
        if (const AstNodeSel* const selp = VN_CAST(nodep, NodeSel)) {
            result.unresolved |= selp->bitp()->user1() != 0;
        } else if (const AstCMethodHard* const atp = VN_CAST(nodep, CMethodHard)) {
            result.unresolved |= atp->method() == VCMethod::ARRAY_AT && atp->pinsp()->user1();
        } else if (const AstNodeFTaskRef* const callp = VN_CAST(nodep, NodeFTaskRef)) {
            result.unresolved |= callp->user1() != 0;
        }
        // The child's root may have become a sampled conditional value.
        if (AstMemberSel* const selp = VN_CAST(nodep, MemberSel)) {
            fromp = selp->fromp();
        } else if (AstMethodCall* const callp = VN_CAST(nodep, MethodCall)) {
            fromp = callp->fromp();
        }
        if (fromp && fromp->isClassHandleValue() && !fromUnresolved) {
            AstVar* const receiverVarp = newGuardVarp(fl, blockp, fromp->dtypep());
            fromp->replaceWith(newGuardRefp(receiverVarp));
            AstNode* const samplep
                = new AstAssign{fl, newGuardRefp(receiverVarp, VAccess::WRITE), fromp};
            samplep->addNext(new AstIf{
                fl, new AstEq{fl, newGuardRefp(receiverVarp), new AstConst{fl, AstConst::Null{}}},
                new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE),
                              new AstConst{fl, AstConst::BitTrue{}}}});
            blockp->addStmtsp(new AstIf{fl, newNoGuardErrorp(errorVarp), samplep});
            result.sampled = result.checked = true;
        }
        return result;
    }
    static AstNodeExpr* newGuardJoinp(FileLine* const fl, AstNodeExpr* const lhsp,
                                      AstNodeExpr* const rhsp, const bool both) {
        if (lhsp && rhsp) {
            if (both) return new AstLogAnd{fl, lhsp, rhsp};
            return new AstLogOr{fl, lhsp, rhsp};
        }
        if (!both) return lhsp ? lhsp : rhsp;
        if (lhsp) VL_DO_DANGLING(lhsp->deleteTree(), lhsp);
        if (rhsp) VL_DO_DANGLING(rhsp->deleteTree(), rhsp);
        return nullptr;
    }
    AstNodeExpr* newGuardProofp(AstNodeExpr* const exprp, AstBegin* const blockp) {
        if (!exprp) return nullptr;
        AstVar* const varp = newGuardVarp(exprp->fileline(), blockp, blockp->findBitDType());
        blockp->addStmtsp(
            new AstAssign{exprp->fileline(), newGuardRefp(varp, VAccess::WRITE), exprp});
        return newGuardRefp(varp);
    }
    struct GuardFlags final {
        AstVar* trueVarp;
        AstVar* falseVarp;
        AstVar* errorVarp;
        bool state;
    };
    using GuardFlagsMap = std::map<const AstNodeExpr*, GuardFlags>;
    static void recordGuardFlags(const AstNodeExpr* const exprp, const GuardResult& result,
                                 GuardFlagsMap& flags) {
        const auto varp = [](AstNodeExpr* const refp) -> AstVar* {
            return refp ? VN_AS(refp, VarRef)->varp() : nullptr;
        };
        flags.emplace(exprp, GuardFlags{varp(result.truep), varp(result.falsep),
                                        varp(result.errorp), !exprp->user1()});
    }
    GuardResult newGuardResult(AstNodeExpr* const exprp, AstBegin* const blockp,
                               GuardFlagsMap& flags) {
        FileLine* const fl = exprp->fileline();
        // Recurse even for all-state predicates: FALSE && ERROR and TRUE || ERROR must sift
        // out the invalid leaf in either operand order (IEEE 1800-2023 18.5.12).
        if (const AstLogNot* const notp = VN_CAST(exprp, LogNot)) {
            const GuardResult child = newGuardResult(notp->lhsp(), blockp, flags);
            const GuardResult result{child.falsep, child.truep, child.errorp};
            recordGuardFlags(exprp, result, flags);
            return result;
        }
        const bool isAnd = VN_IS(exprp, LogAnd);
        if (isAnd || VN_IS(exprp, LogOr)) {
            const AstNodeBiop* const biopp = VN_AS(exprp, NodeBiop);
            const GuardResult lhs = newGuardResult(biopp->lhsp(), blockp, flags);
            const GuardResult rhs = newGuardResult(biopp->rhsp(), blockp, flags);
            AstNodeExpr* const truep
                = newGuardProofp(newGuardJoinp(fl, lhs.truep, rhs.truep, isAnd), blockp);
            AstNodeExpr* const falsep
                = newGuardProofp(newGuardJoinp(fl, lhs.falsep, rhs.falsep, !isAnd), blockp);
            AstNodeExpr* errorp = newGuardJoinp(fl, lhs.errorp, rhs.errorp, false);
            AstNodeExpr* const dominantp = isAnd ? falsep : truep;
            if (errorp && dominantp) {
                errorp = new AstLogAnd{fl, new AstLogNot{fl, dominantp->cloneTree(false)}, errorp};
            }
            const GuardResult result{truep, falsep, newGuardProofp(errorp, blockp)};
            recordGuardFlags(exprp, result, flags);
            return result;
        }
        AstVar* const errorVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        AstAssign* const initp = new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE),
                                               new AstConst{fl, AstConst::BitFalse{}}};
        blockp->addStmtsp(initp);
        // A single clone is edited by moving receiver paths, not cloning each path prefix.
        // Ordinary cloning also preserves legal state calls that are not classified pure.
        AstBegin* const wrapperp = new AstBegin{fl, "[GuardRead]", exprp->cloneTree(false), false};
        const GuardRead read = editGuardReceivers(wrapperp->stmtsp(), blockp, errorVarp);
        AstNodeExpr* const valuep = VN_AS(wrapperp->stmtsp()->unlinkFrBack(), NodeExpr);
        VL_DO_DANGLING(wrapperp->deleteTree(), wrapperp);
        AstNodeExpr* const errorp = read.checked ? newGuardRefp(errorVarp) : nullptr;
        if (!read.sampled) {
            VL_DO_DANGLING(initp->unlinkFrBack()->deleteTree(), initp);
            VL_DO_DANGLING(errorVarp->unlinkFrBack()->deleteTree(), errorVarp);
        }
        if (exprp->user1()) {
            VL_DO_DANGLING(valuep->deleteTree(), valuep);
            const GuardResult result{nullptr, nullptr, errorp};
            recordGuardFlags(exprp, result, flags);
            return result;
        }
        AstVar* const trueVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        AstVar* const falseVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(trueVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::BitFalse{}}});
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(falseVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::BitFalse{}}});
        AstNode* samplep = new AstAssign{fl, newGuardRefp(trueVarp, VAccess::WRITE),
                                         new AstLogNot{fl, new AstLogNot{fl, valuep}}};
        samplep->addNext(new AstAssign{fl, newGuardRefp(falseVarp, VAccess::WRITE),
                                       new AstLogNot{fl, newGuardRefp(trueVarp)}});
        if (errorp) samplep = new AstIf{fl, newNoGuardErrorp(errorVarp), samplep};
        blockp->addStmtsp(samplep);
        const GuardResult result{newGuardRefp(trueVarp), newGuardRefp(falseVarp), errorp};
        recordGuardFlags(exprp, result, flags);
        return result;
    }
    AstNode* newGuardErrorReturnp(AstNode* const nodep) {
        UASSERT_OBJ(m_guardItemp, nodep, "Guard formatting outside a constraint item");
        FileLine* const fl = nodep->fileline();
        if (!m_guardItemp->errorVarp) {
            AstVar* const varp
                = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__VguardItemError"),
                             nodep->findBitDType()};
            varp->funcLocal(true);
            varp->noSubst(true);
            m_guardItemp->errorVarp = varp;
        }
        AstNode* const reportp
            = new AstAssign{fl, newGuardRefp(m_guardItemp->errorVarp, VAccess::WRITE),
                            new AstConst{fl, AstConst::BitTrue{}}};
        // The string is only transport. The item status forces a hard failure outside any
        // negation, soft constraint, or RANDOM guard that could otherwise mask this ERROR.
        reportp->addNext(new AstCReturn{fl, new AstSFormatF{fl, "#b0", false, nullptr}});
        return reportp;
    }
    AstNodeExpr* formatGuardPredicate(AstNodeExpr* const exprp, GuardFlagsMap& flags) {
        FileLine* const fl = exprp->fileline();
        const auto it = flags.find(exprp);
        UASSERT_OBJ(it != flags.end(), exprp, "Missing guard proofs for predicate");
        const GuardFlags proof = it->second;
        flags.erase(it);
        AstNodeExpr* smtp;
        if (AstLogNot* const notp = VN_CAST(exprp, LogNot)) {
            smtp = new AstSFormatF{fl, "(bvnot %s)", false,
                                   formatGuardPredicate(notp->lhsp()->unlinkFrBack(), flags)};
            VL_DO_DANGLING(pushDeletep(exprp), exprp);
        } else if (VN_IS(exprp, LogAnd) || VN_IS(exprp, LogOr)) {
            AstNodeBiop* const biopp = VN_AS(exprp, NodeBiop);
            AstNodeExpr* const lhsp = formatGuardPredicate(biopp->lhsp()->unlinkFrBack(), flags);
            AstNodeExpr* const rhsp = formatGuardPredicate(biopp->rhsp()->unlinkFrBack(), flags);
            smtp = new AstSFormatF{fl, VN_IS(exprp, LogAnd) ? "(bvand %s %s)" : "(bvor %s %s)",
                                   false, AstNode::addNext(lhsp, rhsp)};
            VL_DO_DANGLING(pushDeletep(exprp), exprp);
        } else if (proof.state) {
            // State predicates use the sampled truth, not a repeated possibly invalid read.
            smtp = getConstFormat(newGuardRefp(proof.trueVarp));
            VL_DO_DANGLING(pushDeletep(exprp), exprp);
        } else {
            smtp = VN_AS(iterateSubtreeReturnEdits(exprp), NodeExpr);
        }
        if (!proof.trueVarp && !proof.falseVarp && !proof.errorVarp) return smtp;
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardPredicate"), nullptr, true};
        if (proof.errorVarp) {
            blockp->addStmtsp(
                new AstIf{fl, newGuardRefp(proof.errorVarp), newGuardErrorReturnp(blockp)});
        }
        if (proof.trueVarp) {
            blockp->addStmtsp(
                new AstIf{fl, newGuardRefp(proof.trueVarp),
                          new AstCReturn{fl, new AstSFormatF{fl, "#b1", false, nullptr}}});
        }
        if (proof.falseVarp) {
            blockp->addStmtsp(
                new AstIf{fl, newGuardRefp(proof.falseVarp),
                          new AstCReturn{fl, new AstSFormatF{fl, "#b0", false, nullptr}}});
        }
        blockp->addStmtsp(new AstCReturn{fl, smtp});
        AstCExpr* const cexprp = new AstCExpr{fl};
        cexprp->dtypeSetString();
        cexprp->add("([&]() -> std::string {\n");
        cexprp->add(blockp);
        cexprp->add("})()");
        return new AstSFormatF{fl, "%s", false, cexprp};
    }
    void visit(AstLogIf* nodep) override {
        // The caller knows this is a constraint implication, not a value conditional.
        FileLine* const fl = nodep->fileline();
        AstCond* const condp
            = new AstCond{fl, nodep->lhsp()->unlinkFrBack(), nodep->rhsp()->unlinkFrBack(),
                          new AstConst{fl, AstConst::BitTrue{}}};
        condp->dtypeSetBit();
        condp->user1(true);
        nodep->replaceWith(condp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        editConstraintGuard(condp);
    }
    void editConstraintGuard(AstCond* const nodep) {
        FileLine* const fl = nodep->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), nullptr, true};
        GuardFlagsMap flags;
        const GuardResult result = newGuardResult(nodep->condp(), blockp, flags);
        AstNodeExpr* const predicatep = nodep->condp()->unlinkFrBack();
        nodep->condp(formatGuardPredicate(predicatep, flags));
        UASSERT_OBJ(flags.empty(), nodep, "Unconsumed guard predicate proofs");
        AstSFormatF* const smtp = editSMT(nodep, nodep->condp(), nodep->thenp(), nodep->elsep());
        if (!result.truep && !result.falsep && !result.errorp) {
            VL_DO_DANGLING(blockp->deleteTree(), blockp);
            return;
        }
        AstVar* const trueVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        AstVar* const falseVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        AstVar* const errorVarp
            = result.errorp ? newGuardVarp(fl, blockp, blockp->findBitDType()) : nullptr;
        blockp->addStmtsp(
            new AstAssign{fl, newGuardRefp(trueVarp, VAccess::WRITE),
                          result.truep ? result.truep : new AstConst{fl, AstConst::BitFalse{}}});
        blockp->addStmtsp(
            new AstAssign{fl, newGuardRefp(falseVarp, VAccess::WRITE),
                          result.falsep ? result.falsep : new AstConst{fl, AstConst::BitFalse{}}});
        if (errorVarp) {
            blockp->addStmtsp(
                new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE), result.errorp});
            // ERROR is reported to the active item, not encoded as a boolean value.
            blockp->addStmtsp(
                new AstIf{fl, newGuardRefp(errorVarp), newGuardErrorReturnp(blockp)});
        }
        AstVar* const thenVarp = newGuardVarp(fl, blockp, blockp->findStringDType());
        AstVar* const elseVarp = newGuardVarp(fl, blockp, blockp->findStringDType());
        // Each branch is lowered and stored exactly once, including nested guards. Cloning
        // either branch into a fast path would double the AST at every mixed-guard depth.
        AstNodeExpr* const thenp = VN_AS(smtp->exprsp()->nextp(), NodeExpr);
        AstNodeExpr* const elsep = VN_AS(thenp->nextp(), NodeExpr);
        thenp->replaceWith(newGuardRefp(thenVarp));
        elsep->replaceWith(newGuardRefp(elseVarp));
        blockp->addStmtsp(
            new AstIf{fl, new AstLogNot{fl, newGuardRefp(falseVarp)},
                      new AstAssign{fl, newGuardRefp(thenVarp, VAccess::WRITE), thenp}});
        blockp->addStmtsp(
            new AstIf{fl, new AstLogNot{fl, newGuardRefp(trueVarp)},
                      new AstAssign{fl, newGuardRefp(elseVarp, VAccess::WRITE), elsep}});
        blockp->addStmtsp(
            new AstIf{fl, newGuardRefp(trueVarp), new AstCReturn{fl, newGuardRefp(thenVarp)}});
        blockp->addStmtsp(
            new AstIf{fl, newGuardRefp(falseVarp), new AstCReturn{fl, newGuardRefp(elseVarp)}});
        VNRelinker relinker;
        smtp->unlinkFrBack(&relinker);
        blockp->addStmtsp(new AstCReturn{fl, smtp});
        AstCExpr* const cexprp = new AstCExpr{fl};
        cexprp->dtypeSetString();
        cexprp->add("([&]() -> std::string {\n");
        cexprp->add(blockp);
        cexprp->add("})()");
        relinker.relink(new AstSFormatF{fl, "%s", false, cexprp});
    }
    void visit(AstCond* nodep) override {
        // Value conditionals retain ordinary value semantics. In particular, an invalid value
        // arm must not become boolean FALSE merely because constraint guards use that status.
        if (editFormat(nodep)) return;
        if (nodep->condp()->user1()) {
            editSMT(nodep, nodep->condp(), nodep->thenp(), nodep->elsep());
            return;
        }
        if (isRandModeGate(nodep->condp())) {
            // A generated mode gate may still be an SMT-name prefix. Keep its typed Cond
            // until hoistRandModeOverSelectAndMember lifts it around the complete access.
            iterate(nodep->thenp());
            iterate(nodep->elsep());
            nodep->dtypeSetString();
            return;
        }
        iterate(nodep->thenp());
        iterate(nodep->elsep());
        UASSERT_OBJ(nodep->thenp()->isString() && nodep->elsep()->isString(), nodep,
                    "Value conditional arms not converted to strings");
        FileLine* const fl = nodep->fileline();
        AstCExpr* const cexprp = new AstCExpr{fl};
        cexprp->dtypeSetString();
        cexprp->add("([&]() -> std::string {\n");
        cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VvalueConditional"),
                                 new AstIf{fl, nodep->condp()->unlinkFrBack(),
                                           new AstCReturn{fl, nodep->thenp()->unlinkFrBack()},
                                           new AstCReturn{fl, nodep->elsep()->unlinkFrBack()}},
                                 true});
        cexprp->add("})()");
        nodep->replaceWith(new AstSFormatF{fl, "%s", false, cexprp});
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstReplicate* nodep) override {
        // Biop, but RHS is harmful
        if (editFormat(nodep)) return;
        editSMT(nodep, nodep->srcp());
    }
    void visit(AstSel* nodep) override {
        if (editFormat(nodep)) return;
        VNRelinker handle;
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const msbp = new AstSFormatF{
            fl, "%1d", false,
            new AstAdd{fl, nodep->lsbp()->cloneTreePure(false),
                       new AstConst{fl, static_cast<uint32_t>(nodep->widthConst() - 1)}}};
        AstNodeExpr* const lsbp
            = new AstSFormatF{fl, "%1d", false, nodep->lsbp()->unlinkFrBack(&handle)};
        handle.relink(lsbp);

        editSMT(nodep, nodep->fromp(), lsbp, msbp);
    }
    void visit(AstStructSel* nodep) override {
        if (editFormat(nodep)) return;
        const bool outermost = !m_deferRandModeHoist;
        AstNodeExpr* const origp = outermost ? nodep->cloneTree(false) : nullptr;
        VL_RESTORER(m_structSel);
        m_structSel = true;
        if (VN_IS(nodep->fromp()->dtypep()->skipRefp(), StructDType)) {
            AstNodeExpr* const fromp = nodep->fromp();
            AstStructDType* const structp = VN_AS(fromp->dtypep()->skipRefp(), StructDType);
            markConstrainedRandMember(structp, nodep->name());
            if (isRandQualifiedPath(fromp)) {
                markStructConstrainedRandRecurse(fromp->dtypep());
            } else {
                structp->markConstrainedRand(true);
            }
        }
        // Mark Random for structArray
        if (VN_IS(nodep->fromp(), ArraySel) || VN_IS(nodep->fromp(), CMethodHard)) {
            AstNodeExpr* const fromp = VN_IS(nodep->fromp(), ArraySel)
                                           ? VN_AS(nodep->fromp(), ArraySel)->fromp()
                                           : VN_AS(nodep->fromp(), CMethodHard)->fromp();
            AstStructDType* const structp
                = VN_AS(fromp->dtypep()->skipRefp()->subDTypep()->skipRefp(), StructDType);
            markConstrainedRandMember(structp, nodep->name());
            if (isRandQualifiedPath(fromp)) {
                markStructConstrainedRandRecurse(fromp->dtypep()->skipRefp()->subDTypep());
            } else {
                structp->markConstrainedRand(true);
            }
        }
        {
            VL_RESTORER(m_deferRandModeHoist);
            m_deferRandModeHoist = true;
            iterateChildren(nodep);
        }
        FileLine* const fl = nodep->fileline();
        AstSFormatF* newp = nullptr;
        if (VN_AS(nodep->fromp(), SFormatF)->name() == "%s.%s") {
            newp = new AstSFormatF{fl, "%s.%s." + nodep->name(), false,
                                   VN_AS(nodep->fromp(), SFormatF)->exprsp()->cloneTreePure(true)};
            if (newp->exprsp()->nextp()->name().rfind("#x", 0) == 0)
                newp->exprsp()->nextp()->name("%x");  //  for #x%x to %x
        } else {
            newp = new AstSFormatF{fl, nodep->fromp()->name() + "." + nodep->name(), false,
                                   nullptr};
        }
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        if (origp && !hoistRandModeOverSelectAndMember(newp, origp)) {
            VL_DO_DANGLING(pushDeletep(origp), origp);
        }
    }
    // Width of an integral array index or key in the solver, that of its C++ type
    static int keySmtWidth(const AstNodeDType* const keyDtp) {
        const int width = keyDtp->width();
        if (width <= 8) return 8;
        if (width <= 16) return 16;
        return VL_WORDS_I(width) * VL_EDATASIZE;
    }
    // Format of an array index or key in SMT names, normalized to standard bit widths
    static std::string keyHexFormat(const AstNodeDType* const keyDtp) {
        if (!keyDtp->isIntegralOrPacked()) return "%32x";  // String key
        return "%" + std::to_string(keySmtWidth(keyDtp) / 4) + "x";
    }
    void addStringNamePart(AstNodeExpr* const indexp, const std::string& fmt = "%32x") {
        if (m_nestedAccessp) {
            AstNodeExpr* const bitp = indexp->cloneTreePure(false);
            AstNodeExpr* const bitFormatp = new AstSFormatF{bitp->fileline(), fmt, false, bitp};
            AstSFormatF* const herep
                = new AstSFormatF{indexp->fileline(), "%s.%s", false, bitFormatp};
            m_nestedAccessp->addVarNamePart(herep, indexp->name());
        }
    }
    void visit(AstAssocSel* nodep) override {
        if (editFormat(nodep)) return;
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* const bitp = nodep->bitp();
        const AstNodeDType* const keyDtp = bitp->dtypep()->skipRefp();
        const bool keyIsPackedString = VN_IS(bitp, CvtPackString);
        const bool keyIsString = !keyIsPackedString && keyDtp->isString();
        const bool keyIsIntegral = keyDtp->isIntegralOrPacked();
        const bool elemMemberSel = VN_IS(nodep->backp(), MemberSel);
        AstAssocArrayDType* const assocDtp
            = VN_AS(nodep->fromp()->dtypep()->skipRefp(), AssocArrayDType);
        const bool keyIsRand = keyIsIntegral && isRandIndex(bitp);
        if (keyIsRand && !nodep->fromp()->user1()) {
            // Not an integral value, which editFormat reads through editStateArraySel
            unsupportedStateArraySel(nodep);
            return;
        } else if (keyIsRand && !assocDtp->subDTypep()->skipRefp()->isIntegralOrPacked()) {
            // Such elements, or their members, are solver variables named by the key's value
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: Randomized key into an associative array "
                                         "of non-integral elements");
        }
        // Keep a pre-edit clone for the rand_mode hoist below.
        AstNodeExpr* const origp = nodep->cloneTree(false);
        if (VN_IS(assocDtp->subDTypep()->skipRefp(), ClassRefDType)
            && (keyIsString || keyIsPackedString || keyIsIntegral) && !elemMemberSel) {
            AstNodeExpr* const arrayp = nodep->fromp()->unlinkFrBack();
            AstNodeExpr* const keyp = nodep->bitp()->unlinkFrBack();
            AstCMethodHard* const atp = new AstCMethodHard{fl, arrayp, VCMethod::ARRAY_AT, keyp};
            atp->dtypep(assocDtp->subDTypep()->skipRefp());
            AstCExpr* const handlep = new AstCExpr{fl, ""};
            handlep->add(atp);
            handlep->add(".operator->()");
            handlep->dtypep(nodep->findUInt64DType());
            nodep->replaceWith(getConstFormat(new AstCCast{fl, handlep, 64}));
            VL_DO_DANGLING(origp->deleteTree(), origp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        AstSFormatF* newp = nullptr;
        if (keyIsString) {
            addStringNamePart(bitp);
            VNRelinker handle;
            AstNodeExpr* const idxp = new AstSFormatF{fl, (m_structSel ? "%32x" : "#x%32x"), false,
                                                      nodep->bitp()->unlinkFrBack(&handle)};
            handle.relink(idxp);
            newp = editSMT(nodep, nodep->fromp(), idxp);
        } else if (keyIsPackedString) {
            AstCvtPackString* const stringp = VN_AS(nodep->bitp(), CvtPackString);
            const size_t stringSize = VN_AS(stringp->lhsp(), Const)->width();
            if (stringSize > 128) {
                stringp->v3warn(
                    CONSTRAINTIGN,
                    "Unsupported: Constrained randomization of associative array keys of "
                        << stringSize << "bits, limit is 128 bits");
            }
            addStringNamePart(nodep->bitp());
            VNRelinker handle;
            AstNodeExpr* const idxp = new AstSFormatF{fl, (m_structSel ? "%32x" : "#x%32x"), false,
                                                      stringp->lhsp()->unlinkFrBack(&handle)};
            handle.relink(idxp);
            newp = editSMT(nodep, nodep->fromp(), idxp);
        } else {
            if (keyIsRand) {
                // A random key stays an SMT expression, in the solver's key width
                VNRelinker handle;
                AstNodeExpr* const idxp = newSmtIndexp(nodep->bitp()->unlinkFrBack(&handle), false,
                                                       keySmtWidth(keyDtp));
                handle.relink(idxp);
                newp = editSMT(nodep, nodep->fromp(), idxp);
            } else if (keyIsIntegral) {
                const std::string fmt = (m_structSel ? "" : "#x") + keyHexFormat(keyDtp);
                if (m_nestedAccessp) addStringNamePart(nodep->bitp(), fmt);
                VNRelinker handle;
                AstNodeExpr* const idxp
                    = new AstSFormatF{fl, fmt, false, nodep->bitp()->unlinkFrBack(&handle)};
                handle.relink(idxp);
                newp = editSMT(nodep, nodep->fromp(), idxp);
            } else {
                nodep->bitp()->v3error(
                    "Illegal non-integral expression or subexpression in random constraint."
                    " (IEEE 1800-2023 18.3)");
                if (m_nestedAccessp) m_nestedAccessp->error();
            }
        }
        if (newp && m_structSel && newp->name() == "(select %s %s)") { newp->name("%s.%s"); }
        // The element a random key selects has no current value to hold, as for ARRAY_AT
        if (!newp || keyIsRand || !hoistRandModeOverSelectAndMember(newp, origp)) {
            VL_DO_DANGLING(origp->deleteTree(), origp);
        }
    }
    // Name an element of an array of structs or objects the way the solver registers it
    void renameArrayExpr(AstSFormatF* const newp, const bool objectElem) const {
        if (m_structSel) {
            newp->name("%s.%s");
            // Objects are registered with an unpadded index (createWriteVarForClassFields)
            newp->exprsp()->nextp()->name(objectElem ? "%0x" : "%x");
        }
    }
    // Return SMT condition that the rand indices of select chain 'nodep' are in range, or nullptr
    static AstNodeExpr* newIndexInRangep(const AstArraySel* nodep) {
        AstNodeExpr* condp = nullptr;
        for (const AstArraySel* selp = nodep; selp; selp = VN_CAST(selp->fromp(), ArraySel)) {
            const uint32_t elements
                = VN_AS(selp->fromp()->dtypep()->skipRefp(), UnpackArrayDType)->elementsConst();
            const int width = selp->bitp()->width();
            if (!isRandIndex(selp->bitp()) || (width < 32 && (1U << width) <= elements)) continue;
            FileLine* const fl = selp->fileline();
            AstNodeExpr* const gtep
                = new AstGte{fl, new AstConst{fl, AstConst::WidthedValue{}, width, elements - 1},
                             selp->bitp()->cloneTreePure(false)};
            gtep->user1(true);
            condp = condp ? new AstLogAnd{fl, condp, gtep} : gtep;
            condp->user1(true);
        }
        return condp;
    }
    void visit(AstArraySel* nodep) override {
        if (editFormat(nodep)) return;
        FileLine* const fl = nodep->fileline();
        // An element selected by an out-of-range index reads the default value
        // (IEEE 1800-2023 7.4.6); only an integral element has one to read instead
        if (nodep != m_inRangeSelp && nodep->dtypep()->skipRefp()->isIntegralOrPacked()) {
            if (AstNodeExpr* const inRangep = newIndexInRangep(nodep)) {
                VNRelinker condHandle;
                nodep->unlinkFrBack(&condHandle);
                AstCond* const condp
                    = new AstCond{fl, inRangep, nodep,
                                  new AstConst{fl, AstConst::WidthedValue{}, nodep->width(), 0}};
                condp->user1(true);
                condHandle.relink(condp);
                VL_RESTORER(m_inRangeSelp);
                m_inRangeSelp = nodep;
                iterate(condp);
                return;
            }
        }
        // Of an array of objects, or of arrays of them
        const bool objectElem = VN_IS(arrayElementDTypep(nodep->dtypep()), ClassRefDType);
        VNRelinker handle;
        const bool indexIsRand = isRandIndex(nodep->bitp());
        if (!indexIsRand) {
            // V3Width keeps all index bits; truncate as it did before, as the names of struct
            // and class array elements depend on the index width
            const int selWidth
                = V3Number::log2b(VN_AS(nodep->fromp()->dtypep()->skipRefp(), UnpackArrayDType)
                                      ->declRange()
                                      .hiMaxSelect())
                  + 1;
            if (nodep->bitp()->width() > selWidth) {
                VNRelinker indexHandle;
                AstNodeExpr* const bitp = nodep->bitp()->unlinkFrBack(&indexHandle);
                indexHandle.relink(new AstSel{bitp->fileline(), bitp, 0, selWidth});
            }
        }
        if (m_nestedAccessp) {
            AstNodeExpr* const bitp = nodep->bitp()->cloneTreePure(false);
            AstNodeExpr* const bitFormatp
                = indexIsRand
                      ? new AstSFormatF{bitp->fileline(), bitp->name(), false, nullptr}
                      : new AstSFormatF{bitp->fileline(), objectElem ? "%0x" : "%x", false, bitp};
            AstSFormatF* const herep
                = new AstSFormatF{nodep->fileline(), "%s.%s", false, bitFormatp};
            // The index, under the truncation above
            const AstNodeExpr* const namedp = VN_IS(bitp, Sel) ? VN_AS(bitp, Sel)->fromp() : bitp;
            const AstSub* const subp = VN_CAST(namedp, Sub);
            if (subp && VN_IS(subp->lhsp(), VarRef) && VN_IS(subp->rhsp(), Const)) {
                // A variable index into an array with a nonzero low bound
                m_nestedAccessp->addVarNamePart(herep,
                                                subp->lhsp()->name() + "-" + subp->rhsp()->name());
            } else {
                m_nestedAccessp->addVarNamePart(herep, namedp->name());
            }
            if (indexIsRand) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Randomized index in complex expression");
                m_nestedAccessp->error();
                VL_DO_DANGLING(bitp->deleteTree(), bitp);
                return;
            }
        }
        if (indexIsRand && !nodep->fromp()->user1()) {
            unsupportedStateArraySel(nodep);
        } else if (indexIsRand) {
            // Index depends on rand variable -- keep as SMT symbol.
            // The offset from the low bound is unsigned, even when computed as signed
            AstNodeExpr* const indexp = newSmtIndexp(nodep->bitp()->unlinkFrBack(&handle), false);
            handle.relink(indexp);
            AstSFormatF* const newp = editSMT(nodep, nodep->fromp(), indexp);
            renameArrayExpr(newp, objectElem);
        } else {
            // Index is constant or non-rand -- format as hex literal.
            // Keep a pre-edit clone for the rand_mode hoist below.
            AstNodeExpr* const origp = nodep->cloneTree(false);
            AstNodeExpr* const indexp
                = new AstSFormatF{fl, "#x%8x", false, nodep->bitp()->unlinkFrBack(&handle)};
            handle.relink(indexp);
            AstSFormatF* const newp = editSMT(nodep, nodep->fromp(), indexp);
            renameArrayExpr(newp, objectElem);
            if (!newp || !hoistRandModeOverSelectAndMember(newp, origp)) {
                VL_DO_DANGLING(origp->deleteTree(), origp);
            }
        }
    }
    // True iff exprp is an ARRAY_AT read of a class's own instance mode array.
    static bool isRandModeGate(const AstNodeExpr* exprp) {
        const AstCMethodHard* const atp = VN_CAST(exprp, CMethodHard);
        if (!atp || atp->method() != VCMethod::ARRAY_AT) return false;
        const AstVar* varp = nullptr;
        if (const AstVarRef* const refp = VN_CAST(atp->fromp(), VarRef)) {
            varp = refp->varp();
        } else if (const AstMemberSel* const mselp = VN_CAST(atp->fromp(), MemberSel)) {
            varp = mselp->varp();
        }
        if (!varp) return false;
        const AstClass* const classp = VN_CAST(varp->user2p(), Class);
        return classp && classp->user2p() == varp;
    }
    // Lift a rand_mode Cond above the (select ...) chain of a frozen array element.
    bool hoistRandModeOverSelectAndMember(AstSFormatF* newp, AstNodeExpr* origp) {
        if (m_deferRandModeHoist) return false;
        // Only for selects yielding a non-array element (full chains)
        if (VN_IS(origp->dtypep()->skipRefp(), UnpackArrayDType)) return false;
        // Walk nested "(select %s %s)" frames down to a mode-gating AstCond
        std::vector<AstSFormatF*> frames;
        AstCond* modeCondp = nullptr;
        for (AstSFormatF* curp = newp;
             curp
             && (curp->name() == "(select %s %s)" || curp->name() == "%s.%s"
                 || curp->name().rfind("%s.", 0) == 0);) {
            AstNodeExpr* const firstp = curp->exprsp();
            frames.push_back(curp);
            if (AstCond* const condp = VN_CAST(firstp, Cond)) {
                if (isRandModeGate(condp->condp())) modeCondp = condp;
                break;
            }
            curp = VN_CAST(firstp, SFormatF);
        }
        if (!modeCondp) return false;
        FileLine* const fl = newp->fileline();
        AstNodeExpr* const modep = modeCondp->condp()->unlinkFrBack();
        AstNodeExpr* activep = modeCondp->thenp()->unlinkFrBack();
        // Rebuild the select chain text around the SMT name, innermost first
        for (auto it = frames.rbegin(); it != frames.rend(); ++it) {
            AstNodeExpr* const remainingArgsp = VN_CAST((*it)->exprsp()->nextp(), NodeExpr);
            if (remainingArgsp) { remainingArgsp->unlinkFrBackWithNext(); }
            activep = new AstSFormatF{fl, (*it)->name(), false,
                                      AstNode::addNext(activep, remainingArgsp)};
        }
        AstCond* const hoistp = new AstCond{fl, modep, activep, getConstFormat(origp)};
        hoistp->user1(true);  // Mark as formatted
        newp->replaceWith(hoistp);
        VL_DO_DANGLING(pushDeletep(newp), newp);
        return true;
    }
    void visit(AstMemberSel* nodep) override {
        if (nodep->user1() && editStateArraySel(nodep)) return;
        // Check if rootVar is globalConstrained
        if (nodep->user1() && nodep->varp()->rand().isRandomizable() && nodep->fromp()) {
            FileLine* const fl = nodep->fileline();
            if (m_nestedAccessp) {
                AstSFormatF* const formatp = new AstSFormatF{fl, nodep->name(), false, nullptr};
                m_nestedAccessp->addVarNamePart(new AstSFormatF{fl, "%s.%s", false, formatp},
                                                nodep->name());
            }
            AstNode* rootNodep = nodep->fromp();
            while (const AstMemberSel* const selp = VN_CAST(rootNodep, MemberSel)) {
                rootNodep = selp->fromp();
            }

            AstNodeSel* arraySelp = VN_CAST(rootNodep, ArraySel);
            if (!arraySelp) arraySelp = VN_CAST(rootNodep, AssocSel);

            if (arraySelp) {
                AstNodeDType* const arrayDtp = arraySelp->fromp()->dtypep()->skipRefp();
                AstNodeDType* const elemDtp
                    = arrayDtp->subDTypep() ? arrayDtp->subDTypep()->skipRefp() : nullptr;
                if (elemDtp && VN_IS(elemDtp, ClassRefDType)) {
                    const bool isSimple
                        = nodep->fromp() == rootNodep && VN_IS(arraySelp->fromp(), VarRef);
                    if (!isSimple && !m_nestedAccessp) {
                        m_nestedAccessp = new NestedAccessPath(nodep->cloneTree(false),
                                                               &m_firstExpressionInsideIndexp);
                        AstSFormatF* const formatp
                            = new AstSFormatF{fl, nodep->name(), false, nullptr};
                        m_nestedAccessp->addVarNamePart(
                            new AstSFormatF{fl, "%s.%s", false, formatp}, nodep->name());
                    }
                    VL_RESTORER(m_structSel);
                    m_structSel = true;
                    nodep->user1(true);
                    arraySelp->user1(true);
                    AstNodeExpr* const origp = nodep->cloneTree(false);
                    // The fields of the objects of an inactive array are state variables
                    AstNodeExpr* const activep
                        = isSimple
                              ? newHandlesActivep(m_memberMap, arraySelp->fromp(), true, false)
                              : nullptr;
                    iterateChildren(nodep);
                    AstSFormatF* const newp = new AstSFormatF{fl, "%s." + nodep->name(), false,
                                                              nodep->fromp()->unlinkFrBack()};
                    if (activep) {
                        AstCond* const condp
                            = new AstCond{fl, activep, newp, getConstFormat(origp)};
                        condp->user1(true);  // Mark as formatted
                        nodep->replaceWith(condp);
                    } else {
                        nodep->replaceWith(newp);
                        if (!hoistRandModeOverSelectAndMember(newp, origp))
                            VL_DO_DANGLING(origp->deleteTree(), origp);
                    }
                    VL_DO_DANGLING(pushDeletep(nodep), nodep);
                    VL_DO_DANGLING(delete m_nestedAccessp, m_nestedAccessp);
                    return;
                }
            }
            // Check if the root variable participates in global constraints
            if (const AstVarRef* const varRefp = VN_CAST(rootNodep, VarRef)) {
                AstVar* const constrainedVarp = varRefp->varp();
                if (constrainedVarp->globalConstrained()) {
                    bool const beforeIterate = m_nestedAccessp;
                    // Global constraint - unwrap the MemberSel
                    iterateChildren(nodep);
                    if (beforeIterate) {
                        nodep->replaceWith(new AstSFormatF{fl, "%s." + nodep->name(), false,
                                                           nodep->fromp()->unlinkFrBack()});
                    } else {
                        nodep->replaceWith(nodep->fromp()->unlinkFrBack());
                    }
                    VL_DO_DANGLING(nodep->deleteTree(), nodep);
                    return;
                }
            }
        }
        // Handle MemberSel references created by captureRefByThis()
        if (isCapturedThisSel(nodep)) {
            // Convert to VarRef
            AstVarRef* const varRefp
                = new AstVarRef{nodep->fileline(), nodep->varp(), VAccess::READ};
            varRefp->user1(nodep->varp()->rand().isRandomizable());
            varRefp->classOrPackagep(VN_AS(nodep->user2p(), NodeModule));
            nodep->replaceWith(varRefp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            visit(varRefp);
        } else if (nodep->user1() && VN_IS(nodep->fromp(), CMethodHard)
                   && VN_AS(nodep->fromp(), CMethodHard)->method() == VCMethod::ARRAY_AT) {
            // Class ref array element member access (e.g., items[i].val)
            AstCMethodHard* const cmethodp = VN_AS(nodep->fromp(), CMethodHard);
            AstNodeDType* const arrayDtp = cmethodp->fromp()->dtypep()->skipRefp();
            AstNodeDType* const elemDtp = arrayDtp->subDTypep()->skipRefp();
            if (VN_IS(elemDtp, ClassRefDType)) {
                VL_RESTORER(m_structSel);
                m_structSel = true;
                // The fields of the objects of an inactive array are state variables
                AstNodeExpr* const activep
                    = newHandlesActivep(m_memberMap, cmethodp->fromp(), true, false);
                AstNodeExpr* const origp = activep ? nodep->cloneTree(false) : nullptr;
                iterateChildren(nodep);
                FileLine* const fl = nodep->fileline();
                AstNodeExpr* newp = nullptr;
                if (AstSFormatF* const fromp = VN_CAST(nodep->fromp(), SFormatF)) {
                    if (fromp->name() == "%s.%s") {
                        newp = new AstSFormatF{fl, "%s.%s." + nodep->name(), false,
                                               fromp->exprsp()->cloneTreePure(true)};
                    } else {
                        newp = new AstSFormatF{fl, fromp->name() + "." + nodep->name(), false,
                                               nullptr};
                    }
                } else {
                    newp = new AstSFormatF{fl, nodep->name(), false, nullptr};
                }
                if (activep) {
                    newp = new AstCond{fl, activep, newp, getConstFormat(origp)};
                    newp->user1(true);  // Mark as formatted
                }
                nodep->replaceWith(newp);
                VL_DO_DANGLING(pushDeletep(nodep), nodep);
                return;
            }
            // Not a class ref element, fall through to normal handling
            iterateChildren(nodep);
            nodep->replaceWith(nodep->fromp()->unlinkFrBack());
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        } else if (nodep->user1()) {
            iterateChildren(nodep);
            nodep->replaceWith(nodep->fromp()->unlinkFrBack());
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        } else {
            editFormat(nodep);
        }
    }
    void visit(AstSFormatF* nodep) override {}
    void visit(AstStmtExpr* nodep) override {}
    void visit(AstCStmt* nodep) override {}
    void visit(AstIf* nodep) override {
        // Hoisted runtime-conditional disable_soft statements parked in the
        // constraint-items list by the pre-pass; already fully lowered.
    }
    // Move soft items of a constraint 'if' out to guarded soft constraints after 'lastp'
    void hoistGuardedSofts(AstNode*& lastp, AstConstraintIf* ifp, AstNodeExpr* outerCondp) {
        // The 'if' folds into one hard expression, so each soft item needs its own
        // 'if (guard) soft item' (IEEE 1800-2023 18.5.14). Order is kept, as later soft
        // constraints have priority.
        if (!ifp->exists([](const AstConstraintExpr* const exprp) { return exprp->isSoft(); })) {
            return;
        }
        hoistGuardedSoftItems(lastp, ifp->thensp(),
                              newGuardAnd(outerCondp, ifp->condp()->cloneTreePure(false)));
        if (ifp->elsesp()) {
            hoistGuardedSoftItems(lastp, ifp->elsesp(), newGuardAnd(outerCondp, newNotCond(ifp)));
        }
    }
    // Move soft items of a constraint 'if' branch out to guarded soft constraints
    void hoistGuardedSoftItems(AstNode*& lastp, AstNode* itemsp, AstNodeExpr* condp) {
        for (AstNode *itemp = itemsp, *nextp; itemp; itemp = nextp) {
            nextp = itemp->nextp();
            if (AstConstraintIf* const ifp = VN_CAST(itemp, ConstraintIf)) {
                hoistGuardedSofts(lastp, ifp, condp);
                continue;
            }
            const AstConstraintExpr* const exprp = VN_CAST(itemp, ConstraintExpr);
            AstConstraintForeach* const foreachp = VN_CAST(itemp, ConstraintForeach);
            if (!(exprp && exprp->isSoft())
                && !(foreachp && foreachp->exists([](const AstConstraintExpr* const softp) {
                       return softp->isSoft();
                   }))) {
                continue;
            }
            FileLine* const fl = itemp->fileline();
            itemp->replaceWith(new AstConstraintExpr{fl, new AstConst{fl, AstConst::BitTrue{}}});
            AstNode* hoistp;
            if (foreachp) {
                // 'if (c) foreach (...) body' is 'foreach (...) if (c) body'
                foreachp->addBodyp(new AstConstraintIf{fl, condp->cloneTreePure(false),
                                                       foreachp->bodyp()->unlinkFrBackWithNext(),
                                                       nullptr});
                hoistp = foreachp;
            } else {
                hoistp = new AstConstraintIf{fl, condp->cloneTreePure(false), itemp, nullptr};
            }
            lastp->addNextHere(hoistp);
            lastp = hoistp;
        }
        VL_DO_DANGLING(condp->deleteTree(), condp);
    }
    // Negated condition of a constraint 'if'
    static AstNodeExpr* newNotCond(const AstConstraintIf* ifp) {
        AstNodeExpr* const notp = new AstLogNot{ifp->fileline(), ifp->condp()->cloneTree(false)};
        notp->user1(ifp->condp()->user1());
        return notp;
    }
    // Condition 'outerCondp && condp', taking ownership of condp
    static AstNodeExpr* newGuardAnd(AstNodeExpr* outerCondp, AstNodeExpr* condp) {
        if (!outerCondp) return condp;
        AstNodeExpr* const andp
            = new AstLogAnd{condp->fileline(), outerCondp->cloneTreePure(false), condp};
        andp->user1(outerCondp->user1() || condp->user1());
        return andp;
    }
    void visit(AstConstraintIf* nodep) override {
        // Outside a fold, this if's branches are folded here and m_constraintVars collects
        // their names for the constraint replacing it; a nested if adds to its parent's fold
        const bool foldOwner = !m_wantSingle;
        VL_RESTORER(m_guardItemp);
        GuardItem item;
        if (foldOwner) m_guardItemp = &item;
        UASSERT_OBJ(!foldOwner || m_constraintVars.empty(), nodep,
                    "Constraint names of an earlier fold were not taken over");
        AstNodeExpr* newp = nullptr;
        FileLine* const fl = nodep->fileline();
        // A single soft item under 'if' without 'else' stays soft, as made by hoistGuardedSofts
        const AstConstraintExpr* const softp = VN_CAST(nodep->thensp(), ConstraintExpr);
        const bool isSoft = softp && softp->isSoft() && !softp->nextp() && !nodep->elsesp();
        if (foldOwner && !isSoft) {
            AstNode* lastp = nodep;
            hoistGuardedSofts(lastp, nodep, nullptr);
        }
        AstNodeExpr* const thenp = editSingle(fl, nodep->thensp());
        AstNodeExpr* const elsep = editSingle(fl, nodep->elsesp());
        if (thenp && elsep) {
            // Keep guard origin explicit: both arms are constraint implications, not a value
            // conditional whose ERROR handling could change an enclosing value expression.
            AstNodeExpr* const condp = nodep->condp()->unlinkFrBack();
            AstLogNot* const notp = new AstLogNot{fl, condp->cloneTree(false)};
            notp->user1(condp->user1());
            AstLogIf* const thenGuardp = new AstLogIf{fl, condp, thenp};
            AstLogIf* const elseGuardp = new AstLogIf{fl, notp, elsep};
            thenGuardp->user1(true);
            elseGuardp->user1(true);
            newp = new AstLogAnd{fl, thenGuardp, elseGuardp};
        } else if (thenp) {
            newp = new AstLogIf{fl, nodep->condp()->unlinkFrBack(), thenp};
        } else if (elsep) {
            AstNodeExpr* const condp = nodep->condp()->unlinkFrBack();
            AstLogNot* const notp = new AstLogNot{fl, condp};
            notp->user1(condp->user1());  // Solve the negated condition if it is rand-dependent
            newp = new AstLogIf{fl, notp, elsep};
        }
        if (newp) {
            newp->dtypeSetBit();  // Result is boolean (prevents bare-var != 0 wrapping)
            newp->user1(true);  // Assume result-dependent
            AstConstraintExpr* const exprp = new AstConstraintExpr{fl, newp};
            exprp->isSoft(isSoft);
            nodep->replaceWith(exprp);
            // Iterated next (AstNode::iterateAndNext), and takes over the folded names
            if (foldOwner) {
                m_foldTakerp = exprp;
                m_foldErrorVarp = item.errorVarp;
            }
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstGenBlock* nodep) override {
        // Dubious but this is what we used to do. Does that mean no randomzie
        // methods work under a generage block?
    }
    void visit(AstBegin* nodep) override {}
    void visit(AstConstraintForeach* nodep) override {
        // Convert to plain foreach
        FileLine* const fl = nodep->fileline();

        if (!nodep->bodyp()) {
            nodep->unlinkFrBack();
        } else if (m_wantSingle) {
            AstNodeExpr* const itemp = editSingle(fl, nodep->bodyp());
            if (!itemp) {  // All items were ignored with a warning
                VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
                return;
            }
            AstCStmt* const cstmtp = new AstCStmt{fl};
            cstmtp->add("ret += \" \";\n");
            cstmtp->add("ret += ");
            cstmtp->add(itemp);
            cstmtp->add(";");
            AstNode* const bodyp = prependDistPreamble(nodep, cstmtp);
            AstCExpr* const cexprp = new AstCExpr{fl};
            cexprp->dtypeSetString();
            cexprp->add("([&]{\nstd::string ret;\n");
            cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                                     new AstForeach{fl, nodep->headerp()->unlinkFrBack(), bodyp},
                                     true});
            cexprp->add("return ret.empty() ? \"#b1\" : \"(bvand\" + ret + \")\";\n})()");
            nodep->replaceWith(new AstSFormatF{fl, "%s", false, cexprp});
        } else {
            VL_RESTORER(m_foreachp);
            VL_RESTORER_COPY(m_foreachIdxVars);
            m_foreachp = nodep;
            for (AstNode* elemp = nodep->headerp()->elementsp(); elemp; elemp = elemp->nextp()) {
                if (const AstVar* const varp = VN_CAST(elemp, Var)) m_foreachIdxVars.insert(varp);
            }
            iterateAndNextNull(nodep->bodyp());
            if (!nodep->bodyp()) {  // All items were ignored with a warning
                VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
                return;
            }
            AstNode* const bodyp
                = prependDistPreamble(nodep, nodep->bodyp()->unlinkFrBackWithNext());
            nodep->replaceWith(
                new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                             new AstForeach{fl, nodep->headerp()->unlinkFrBack(), bodyp}, true});
        }
        UASSERT_OBJ(!nodep->user3p(), nodep, "Dist bucket preamble not injected into foreach");
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    void visit(AstConstraintBefore* nodep) override {
        // Generate solveBefore() calls for each (lhs, rhs) variable pair.
        // Do NOT iterate children -- these are variable references, not constraint expressions.
        if (m_wantSingle) {
            // IEEE 1800-2023 A.1.10 allows solve-before only as a constraint_block_item.
            // Some simulators accept it nested, Verilator inside foreach, but a conditional
            // is lowered to a single expression with no place for the ordering. Ignoring it
            // only changes the distribution of solutions (18.5.9).
            nodep->v3warn(CONSTRAINTIGN, "Ignoring solve-before inside conditional constraint;"
                                         " IEEE 1800-2023 A.1.10 allows it only directly in"
                                         " a constraint block");
            VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
            return;
        }
        FileLine* const fl = nodep->fileline();
        AstNodeModule* const genModp = VN_AS(m_genp->user2p(), NodeModule);

        for (AstNodeExpr* lhsp = nodep->lhssp(); lhsp; lhsp = VN_CAST(lhsp->nextp(), NodeExpr)) {
            AstNodeExpr* const lhsTestp = buildSolveBeforeNameExpr(fl, lhsp);
            if (!lhsTestp) {
                lhsp->v3fatalSrc("Unexpected expression type in solve...before lhs");
                continue;
            }
            VL_DO_DANGLING(lhsTestp->deleteTree(), lhsTestp);
            for (AstNodeExpr* rhsp = nodep->rhssp(); rhsp;
                 rhsp = VN_CAST(rhsp->nextp(), NodeExpr)) {
                AstNodeExpr* const rhsNamep = buildSolveBeforeNameExpr(fl, rhsp);
                if (!rhsNamep) {
                    rhsp->v3fatalSrc("Unexpected expression type in solve...before rhs");
                    continue;
                }
                AstCMethodHard* const callp = new AstCMethodHard{
                    fl, new AstVarRef{fl, genModp, m_genp, VAccess::READWRITE},
                    VCMethod::RANDOMIZER_SOLVE_BEFORE};
                callp->dtypeSetVoid();
                callp->addPinsp(buildSolveBeforeNameExpr(fl, lhsp));
                callp->addPinsp(rhsNamep);
                nodep->addHereThisAsNext(callp->makeStmt());
            }
        }
        VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
    }
    void visit(AstConstraintUnique* nodep) override {
        FileLine* const fl = nodep->fileline();

        AstBegin* initp;
        AstVar* genVarp;
        AstNodeModule* genModp = nullptr;
        if (m_inlineInitBlockp) {
            // A randomize() with {} inline block's own per-invocation
            // function/generator, as every other write_var call site in this
            // visitor already uses. Registering there instead of unconditionally
            // into the class's constructor/persistent generator lets the
            // registration re-run on every call, seeing the array's current
            // (possibly just-resolved-this-call) size, rather than freezing it at
            // construction time. Its generator is a function-local var referenced
            // directly, with no module qualifier (genModp stays null).
            initp = m_inlineInitBlockp;
            genVarp = m_genp;
        } else {
            initp = newInitBlockp(VN_AS(m_memberMap.findMember(m_classp, "new"), NodeFTask));
            genVarp = getRandomGenerator(m_classp);
            UASSERT_OBJ(genVarp, nodep, "No generator variable");
            genModp = VN_AS(genVarp->user2p(), NodeModule);
            UASSERT_OBJ(genModp, nodep, "genVarp has no NodeModule set");
        }
        // Every remaining ConstraintExprVisitor construction site passes a non-null
        // genp whenever m_classp is set (class-level: only reached inside
        // `if (genp) {...}` in visit(AstClass*); with{}-block: always a freshly
        // created local generator var), so genVarp can no longer be null here.
        UASSERT_OBJ(genVarp, nodep, "No generator variable");
        const auto genVarRefp = [&](VAccess access) -> AstVarRef* {
            return genModp ? new AstVarRef{fl, genModp, genVarp, access}
                           : new AstVarRef{fl, genVarp, access};
        };

        // Registration calls emitted where the unique statement stood, so they end up
        // in the constraint setup task and re-run on every randomize()
        AstNode* setupStmtsp = nullptr;
        // Under a condition the distinctness must instead become part of the guarded
        // constraint expression, which needs an element count known at verilation time
        std::vector<std::string> smtExprs;
        for (AstNode* const itemp : nodep->rangespList()) {
            // An array of the class, or of a member object reached through member selects
            AstMemberSel* memberselp = VN_CAST(itemp, MemberSel);
            // A variable of the class itself, captured as this.x in a randomize() with
            if (memberselp && isCapturedThisSel(memberselp)) memberselp = nullptr;
            const AstNode* rootp = itemp;
            while (const AstMemberSel* const selp = VN_CAST(rootp, MemberSel)) {
                rootp = selp->fromp();
            }
            if (VN_IS(rootp, VarRef)) {
                AstVar* const varp = VN_IS(itemp, MemberSel) ? VN_AS(itemp, MemberSel)->varp()
                                                             : VN_AS(itemp, VarRef)->varp();
                const std::string smtName
                    = memberselp ? buildMemberPath(memberselp) : varp->name();
                AstNodeModule* const varModp = VN_AS(varp->user2p(), NodeModule);
                UASSERT_OBJ(varModp, nodep, "varp has no NodeModule set");
                AstNodeDType* const dtypep = varp->dtypep()->skipRefp();

                const static auto dynDTypeSupported
                    = [](const AstNodeDType* const dtypep) -> bool {
                    return VN_IS(dtypep, DynArrayDType) || VN_IS(dtypep, QueueDType)
                           || VN_IS(dtypep, AssocArrayDType);
                };

                // Establish it is an array before asking for its element type
                uint64_t elemWidth;
                uint32_t staticSize = 0;  // Element count, zero when only known at run time
                if (const AstUnpackArrayDType* const up = VN_CAST(dtypep, UnpackArrayDType)) {
                    const AstRange* const rangep = up->rangep();
                    UASSERT_OBJ(rangep && VN_IS(rangep->leftp(), Const)
                                    && VN_IS(rangep->rightp(), Const),
                                nodep, "Unpack array does not have a constant range");
                    staticSize = up->elementsConst();
                    if (staticSize > 100) {
                        nodep->v3warn(
                            CONSTRAINTIGN,
                            "Unsupported: Unique constraint on static arrays of size > 100");
                        continue;
                    }
                    elemWidth = static_cast<uint64_t>(varp->dtypep()->width());
                } else if (dynDTypeSupported(dtypep)) {
                    elemWidth = static_cast<uint64_t>(dtypep->subDTypep()->width());
                } else {
                    nodep->v3warn(CONSTRAINTIGN, "Unsupported: Unique constraint on "
                                                     << dtypep->prettyDTypeName(false));
                    continue;
                }

                // Ensure it is ONLY 1-D by checking that the element type is not an array/queue
                const AstNodeDType* const subp = dtypep->subDTypep()->skipRefp();
                if (VN_IS(subp, NodeArrayDType) || VN_IS(subp, QueueDType)
                    || VN_IS(subp, DynArrayDType) || VN_IS(subp, AssocArrayDType)
                    || VN_IS(subp, WildcardArrayDType)) {
                    nodep->v3warn(CONSTRAINTIGN,
                                  "Unsupported: Unique constraint on multidimensional arrays");
                    continue;
                }

                if (m_wantSingle && !staticSize) {
                    nodep->v3warn(CONSTRAINTIGN,
                                  "Unsupported: Unique constraint on dynamically sized array "
                                  "inside conditional constraint");
                    continue;
                }

                // A with{}-block's own registration must use the per-instance
                // m_inlineWrittenVars (fresh for each ConstraintExprVisitor pass), not
                // the permanent, compile-time-once AstVar::user3() -- otherwise a
                // unique{} target that isn't itself size-constrained (so the two-phase
                // solve's manual refresh loop doesn't cover it) never gets write_var'd
                // again on the second pass, once the class generator copy in between
                // has dropped its first-pass registration. This mirrors the general
                // (non-unique) write_var dedup a few hundred lines up, which already
                // makes exactly this distinction.
                const bool alreadyWritten = m_inlineInitBlockp
                                                ? m_inlineWrittenVars.count(varp->name()) > 0
                                                : varp->user3();
                if (memberselp) {
                    // Registered as by a member select in any other constraint
                    std::set<std::string> names;  // Only a hard constraint lists its names
                    VL_RESTORER(m_constraintVarsp);
                    m_constraintVarsp = m_wantSingle ? &m_constraintVars : &names;
                    iterate(itemp);
                } else if (!alreadyWritten) {
                    varp->user3(true);  // Solver owns it; __VBasicRand must not overwrite
                    if (m_inlineInitBlockp) m_inlineWrittenVars.insert(varp->name());
                    // Convert to C string
                    AstNodeExpr* const varnamep = new AstCExpr{
                        fl, AstCExpr::Pure{}, "\"" + varp->name() + "\"", varp->width()};

                    AstCMethodHard* const writeVarCallp = new AstCMethodHard{
                        fl, genVarRefp(VAccess::READ), VCMethod::RANDOMIZER_WRITE_VAR};
                    AstVarRef* const argVarRefp = new AstVarRef{fl, varp, VAccess::READ};
                    if (m_classp) argVarRefp->classOrPackagep(varModp);
                    writeVarCallp->addPinsp(argVarRefp);
                    writeVarCallp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, elemWidth});
                    writeVarCallp->addPinsp(varnamep);
                    writeVarCallp->addPinsp(new AstConst{fl, 1});  // Dimension
                    const RandomizeMode randMode = {.asUQuad = varp->user1()};
                    if (randMode.usesMode) {
                        writeVarCallp->addPinsp(
                            new AstConst{fl, AstConst::Unsized64{}, randMode.index});
                    }
                    writeVarCallp->dtypeSetVoid();
                    initp->addStmtsp(new AstStmtExpr{fl, writeVarCallp});
                }

                // A solver-sized container is resized between solve passes; joining the
                // size-constrained set gets its element table refreshed in between
                if (!memberselp && varp->user4p() && m_sizeConstrainedArraysp) {
                    m_sizeConstrainedArraysp->insert(varp);
                }

                if (m_wantSingle) {
                    // Fewer than two elements are trivially distinct
                    if (staticSize < 2) continue;
                    // Named in the text below, so the folded constraint must record it too.
                    // Visited from the if's fold, outside any constraint expression, so
                    // m_constraintVarsp is not set: add to the fold's names directly
                    m_constraintVars.insert(smtName);
                    std::string exprStr = "(__Vbv (distinct";
                    for (uint32_t i = 0; i < staticSize; ++i) {
                        exprStr += " (select " + smtName + " #x";
                        for (int shift = 28; shift >= 0; shift -= 4) {
                            exprStr += "0123456789abcdef"[(i >> shift) & 0xf];
                        }
                        exprStr += ')';
                    }
                    smtExprs.emplace_back(exprStr + "))");
                    continue;
                }

                AstNodeExpr* const namep = new AstConst{fl, AstConst::String{}, smtName};
                AstCMethodHard* const randUniqueCallp = new AstCMethodHard{
                    fl, genVarRefp(VAccess::READ), VCMethod::RANDOMIZER_UNIQUE, namep};
                randUniqueCallp->dtypep(nodep->findVoidDType());
                randUniqueCallp->addPinsp(new AstConst{fl, *m_uniqueConstraintIdp});
                setupStmtsp = AstNode::addNext(setupStmtsp, new AstStmtExpr{fl, randUniqueCallp});
            } else {
                itemp->v3warn(CONSTRAINTIGN, "Unsupported: Unique constraint on this expression");
            }
        }
        ++(*m_uniqueConstraintIdp);
        if (m_wantSingle && !smtExprs.empty()) {
            std::string exprStr = smtExprs.front();
            if (smtExprs.size() > 1) {
                exprStr = "(bvand";
                for (const std::string& oneExprp : smtExprs) exprStr += " " + oneExprp;
                exprStr += ')';
            }
            AstSFormatF* const newp = new AstSFormatF{fl, exprStr, false, nullptr};
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (setupStmtsp) nodep->addHereThisAsNext(setupStmtsp);
        nodep->unlinkFrBack();
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    AstNode* wrapGuardItemCall(AstCMethodHard* const callp, AstNode* const stmtp,
                               AstVar* const errorVarp) {
        FileLine* const fl = callp->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardItem"), errorVarp, true};
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::BitFalse{}}});
        AstVar* const textVarp = newGuardVarp(fl, blockp, blockp->findStringDType());
        AstNodeExpr* const textp = callp->pinsp();
        textp->replaceWith(newGuardRefp(textVarp));
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(textVarp, VAccess::WRITE), textp});
        // ERROR is always a hard failure, including a soft item or an expression that negates
        // the guard's boolean payload. Evaluate all needed formatting before testing status.
        AstCMethodHard* const failp = callp->cloneTree(false);
        const bool wasSoft = failp->method() == VCMethod::RANDOMIZER_SOFT;
        failp->method(VCMethod::RANDOMIZER_HARD);
        AstNodeExpr* const oldTextp = failp->pinsp();
        oldTextp->replaceWith(new AstSFormatF{fl, "#b0", false, nullptr});
        VL_DO_DANGLING(pushDeletep(oldTextp), oldTextp);
        if (wasSoft) { failp->pinsp()->addNextHere(new AstCExpr{fl, AstCExpr::Pure{}, "{}"}); }
        blockp->addStmtsp(new AstIf{fl, newGuardRefp(errorVarp), failp->makeStmt(), stmtp});
        return blockp;
    }
    void visit(AstConstraintExpr* nodep) override {
        // IEEE 1800-2023 18.5.13: 'disable soft' is a meta-level directive on
        // the constraint graph, lowered to a void RANDOMIZER_DISABLE_SOFT
        // call.  Conditional occurrences (if / foreach / implication body)
        // are rewritten by extractConditionalDisableSofts() before this
        // visitor runs, so anything we see here is unconditional.
        VL_RESTORER(m_firstExpressionInsideIndexp);
        VL_RESTORER(m_guardItemp);
        GuardItem item;
        if (!m_wantSingle) m_guardItemp = &item;
        // Outside a fold this constraint is emitted here with only its own names: those it
        // records, plus the folded names when it replaces an if (see visit(AstConstraintIf*))
        std::set<std::string> vars;
        if (!m_wantSingle) {
            if (nodep == m_foldTakerp) {
                vars.swap(m_constraintVars);
                item.errorVarp = m_foldErrorVarp;
                m_foldErrorVarp = nullptr;
                m_foldTakerp = nullptr;
            }
            UASSERT_OBJ(m_constraintVars.empty(), nodep,
                        "Constraint names carried over from another constraint");
        }
        VL_RESTORER(m_constraintVarsp);
        m_constraintVarsp = m_wantSingle ? &m_constraintVars : &vars;
        if (nodep->isDisableSoft()) {
            nodep->replaceWith(buildDisableSoftCallStmt(nodep));
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }
        // IEEE 1800-2023 18.5.1: A bare expression used as a constraint is
        // implicitly treated as "expr != 0" when wider than 1 bit.
        // Must wrap before iterateChildren, which converts to SMT format.
        {
            AstNodeExpr* const exprp = nodep->exprp();
            if (exprp->width() > 1) {
                FileLine* const fl = exprp->fileline();
                const V3Number numZero{fl, exprp->width(), 0};
                AstNodeExpr* const neqp
                    = new AstNeq{fl, exprp->unlinkFrBack(), new AstConst{fl, numZero}};
                neqp->user1(true);  // Mark as rand-dependent for SMT path
                nodep->exprp(neqp);
            }
        }
        VL_RESTORER(m_sizeGatep);
        m_sizeGatep = nullptr;
        iterateChildren(nodep);
        if (m_sizeGatep) {
            AstLogIf* const gatedp
                = new AstLogIf{nodep->fileline(), m_sizeGatep, nodep->exprp()->unlinkFrBack()};
            gatedp->dtypeSetBit();
            gatedp->user1(true);
            nodep->exprp(gatedp);
            iterate(gatedp);
        }
        if (m_wantSingle) {
            nodep->replaceWith(nodep->exprp()->unlinkFrBack());
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }
        // Emit as soft or hard constraint per IEEE 1800-2023 18.5.13
        const VCMethod method
            = nodep->isSoft() ? VCMethod::RANDOMIZER_SOFT : VCMethod::RANDOMIZER_HARD;
        AstCMethodHard* const callp = new AstCMethodHard{
            nodep->fileline(),
            new AstVarRef{nodep->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                          VAccess::READWRITE},
            method, nodep->exprp()->unlinkFrBack()};
        callp->dtypeSetVoid();
        if (method == VCMethod::RANDOMIZER_HARD) {
            // hard() pin layout is asserted in EmitCFunc: the variable list is always pin 2
            callp->addPinsp(
                new AstCExpr{nodep->fileline(), AstCExpr::Pure{}, constraintVarsList(vars)});
        }
        // Pass filename, lineno, and source as separate arguments
        // This allows EmitC to call protect() on filename, similar to VL_STOP
        // Add filename parameter
        callp->addPinsp(new AstCExpr{nodep->fileline(), AstCExpr::Pure{},
                                     "\"" + nodep->fileline()->filename() + "\""});
        // Add line number parameter
        const uint32_t lineno = static_cast<uint32_t>(nodep->fileline()->lineno());
        callp->addPinsp(new AstConst{nodep->fileline(), lineno});
        // Add source text parameter (empty if --protect-ids to avoid source leakage)
        std::string prettyText;
        if (!v3Global.opt.protectIds()) {
            prettyText = nodep->fileline()->prettySource();
            size_t pos = 0;
            while ((pos = prettyText.find('"', pos)) != std::string::npos) {
                prettyText.insert(pos, "\\");
                pos += std::strlen("\\\"");
            }
        }
        callp->addPinsp(
            new AstCExpr{nodep->fileline(), AstCExpr::Pure{}, "\"" + prettyText + "\""});
        AstNode* stmtp = callp->makeStmt();
        if (item.errorVarp) stmtp = wrapGuardItemCall(callp, stmtp, item.errorVarp);
        if (!m_funcArgNames.empty()) {
            // Add the constraint once the arguments of its function calls are solved
            m_funcCalls.push_back({nodep->fileline(), m_funcArgNames, m_itemVarNames});
            AstCMethodHard* const readyp = new AstCMethodHard{
                nodep->fileline(),
                new AstVarRef{nodep->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                              VAccess::READ},
                VCMethod::RANDOMIZER_FUNC_ARGS_READY, newNameListp(nodep->fileline())};
            readyp->dtypeSetBit();
            stmtp = new AstIf{nodep->fileline(), readyp, stmtp};
        }
        m_funcArgNames.clear();
        m_itemVarNames.clear();
        nodep->replaceWith(stmtp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
    }
    // C++ initializer list of the current item's function argument names
    AstCExpr* newNameListp(FileLine* fl) const {
        std::string list;
        for (const std::string& name : m_funcArgNames) {
            list += (list.empty() ? "{\"" : ", \"") + name + "\"";
        }
        return new AstCExpr{fl, AstCExpr::Pure{}, list + "}"};
    }
    void visit(AstCMethodHard* nodep) override {
        if (editFormat(nodep)) return;
        FileLine* const fl = nodep->fileline();

        if (nodep->method() == VCMethod::ARRAY_AT) {
            addStringNamePart(nodep->pinsp(), "%x");
            const bool indexIsRand = isRandIndex(nodep->pinsp());
            if (nodep->fromp()->user1()) {
                // Queue/dynamic element: pre-edit clone for the rand_mode hoist, non-rand index
                // only. A std::randomize() with-clause argument carries no rand qualifier of its
                // own but is still part of the solve.
                {
                    const AstNode* const basep = nodep->baseFromp(true);
                    if (basep->name() == "__Vthis"
                        && VN_AS(basep->backp(), MemberSel)->varp()->isRand()) {
                        nodep->fromp()->v3warn(E_UNSUPPORTED,
                                               "Unsupported: Complex expression captured from "
                                               "current scope with randomized variable");
                        return;
                    }
                }
                AstNodeExpr* const origp = indexIsRand ? nullptr : nodep->cloneTree(false);
                const AstVarRef* const baseRefp
                    = m_structSel ? VN_CAST(nodep->fromp()->baseFromp(true), VarRef) : nullptr;
                if (baseRefp && VN_IS(nodep->pinsp(), Const)
                    && VN_IS(baseRefp->varp()->dtypep()->skipRefp(), DynArrayDType)
                    && m_prepareConstrainedArraysp) {
                    AstNodeExpr* const indexp = nodep->pinsp()->cloneTreePure(false);
                    AstNodeExpr* const arrayp = nodep->fromp()->cloneTreePure(false);
                    AstCMethodHard* const currentSizep
                        = new AstCMethodHard{fl, arrayp->cloneTreePure(false), VCMethod::DYN_SIZE};
                    currentSizep->dtypeSetInt();
                    AstNodeExpr* const inRangeRequiredp = new AstLogAnd{
                        fl,
                        new AstLteS{fl,
                                    new AstConst{fl, AstConst::WidthedValue{}, indexp->width(), 0},
                                    indexp->cloneTreePure(false)},
                        new AstGteS{fl, indexp->cloneTreePure(false), currentSizep}};
                    AstCMethodHard* const resizep
                        = new AstCMethodHard{fl, arrayp, VCMethod::DYN_RESIZE,
                                             new AstAdd{fl, indexp, new AstConst{fl, 1}}};
                    resizep->dtypeSetVoid();
                    m_prepareConstrainedArraysp->addStmtsp(
                        new AstIf{fl, inRangeRequiredp, resizep->makeStmt()});
                }
                AstCMethodHard* const sizep
                    = m_structSel ? new AstCMethodHard{fl, nodep->fromp()->cloneTreePure(false),
                                                       VCMethod::DYN_SIZE}
                                  : nullptr;
                AstNodeExpr* const originalPinp = nodep->pinsp();
                if (indexIsRand) {
                    // A negative index stays out of range when sign extended
                    AstNodeExpr* const pinp = nodep->pinsp()->unlinkFrBack();
                    nodep->addPinsp(newSmtIndexp(pinp, pinp->isSigned()));
                }
                iterateChildren(nodep);
                AstNodeExpr* const pinp = nodep->pinsp()->unlinkFrBack();
                AstSFormatF* newp;
                if (m_structSel) {
                    if (AstSFormatF* const sformatfp = VN_CAST(pinp, SFormatF)) {
                        sformatfp->name("%x");
                    }
                    AstNodeExpr* const argsp
                        = AstNode::addNext(nodep->fromp()->unlinkFrBack(), pinp);
                    sizep->dtypeSetInt();
                    AstLogAnd* const condp
                        = new AstLogAnd{fl,
                                        new AstLteS{fl,
                                                    new AstConst{fl, AstConst::WidthedValue{},
                                                                 originalPinp->width(), 0},
                                                    originalPinp->cloneTreePure(false)},
                                        new AstLtS{fl, originalPinp->cloneTreePure(false), sizep}};
                    m_conditionp = m_conditionp ? new AstLogAnd{fl, m_conditionp, condp} : condp;
                    newp = new AstSFormatF{fl, "%s.%s", false, argsp};
                } else {
                    newp = createSolverArrDerefp(fl, nodep->fromp()->unlinkFrBack(), pinp);
                }
                nodep->replaceWith(newp);
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
                if (origp && !hoistRandModeOverSelectAndMember(newp, origp)) {
                    VL_DO_DANGLING(origp->deleteTree(), origp);
                }

            } else if (indexIsRand) {
                unsupportedStateArraySel(nodep);
            } else {
                nodep->user1(false);
                UASSERT_OBJ(editFormat(nodep), nodep,
                            "editFormat should return true when user1 is false");
            }
            return;
        }

        if (nodep->method() == VCMethod::ARRAY_INSIDE) {
            const bool randArr = nodep->fromp()->user1();
            gateOnCurrentSize(nodep->fromp());

            AstVar* const newVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, "__Vinside", nodep->findIntDType()};
            AstNodeExpr* const idxRefp = new AstVarRef{nodep->fileline(), newVarp, VAccess::READ};
            AstForeachHeader* const headerp
                = new AstForeachHeader{fl, nodep->fromp()->cloneTreePure(false), newVarp};
            AstNodeExpr* const selp = newSel(nodep->fileline(), nodep->fromp(), idxRefp);
            selp->user1(randArr);
            AstNode* const itemp = new AstEq{fl, selp, nodep->pinsp()->unlinkFrBack()};
            itemp->user1(true);

            AstCStmt* const cstmtp = new AstCStmt{fl};
            cstmtp->add("ret += \" \";\n");
            cstmtp->add("ret += ");
            cstmtp->add(iterateSubtreeReturnEdits(itemp));
            cstmtp->add(";");
            AstCExpr* const cexprp = new AstCExpr{fl};
            cexprp->dtypeSetString();
            cexprp->add("([&]{\nstd::string ret;\n");
            cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                                     new AstForeach{fl, headerp, cstmtp}, true});
            cexprp->add("return ret.empty() ? \"#b0\" : \"(bvor\" + ret + \")\";\n})()");
            nodep->replaceWith(new AstSFormatF{fl, "%s", false, cexprp});
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }

        // Array reduction methods (sum, product, and, or, xor)
        if (nodep->method() == VCMethod::ARRAY_R_SUM
            || nodep->method() == VCMethod::ARRAY_R_PRODUCT
            || nodep->method() == VCMethod::ARRAY_R_AND || nodep->method() == VCMethod::ARRAY_R_OR
            || nodep->method() == VCMethod::ARRAY_R_XOR) {

            AstWith* const withp = nodep->withp();

            // For 'with' clause: check array size limit and item.index support
            if (withp) {
                if (AstUnpackArrayDType* const adtypep
                    = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), UnpackArrayDType)) {
                    const int arraySize = adtypep->elementsConst();
                    if (arraySize > v3Global.opt.constraintArrayLimit()) {
                        nodep->v3warn(CONSTRAINTIGN,
                                      "Constraint array reduction ignored (array size "
                                          + cvtToStr(arraySize)
                                          + " exceeds --constraint-array-limit of "
                                          + cvtToStr(v3Global.opt.constraintArrayLimit())
                                          + "), treating as state");
                        nodep->user1(false);
                        if (editFormat(nodep)) return;
                        nodep->v3fatalSrc("Method not handled in constraints? " << nodep);
                        return;
                    }
                }
            }

            // For without 'with' clause: need random array for variable registration
            const bool hasRandomArray = nodep->fromp()->user1();
            if (!withp && !hasRandomArray) {
                // No 'with' clause and not a random array - can't handle
                nodep->v3warn(CONSTRAINTIGN,
                              "Unsupported: randomizing this expression, treating as state");
                nodep->user1(false);
                if (editFormat(nodep)) return;
                nodep->v3fatalSrc("Method not handled in constraints? " << nodep);
                return;
            }
            if (unsupportedRowSel(nodep->fromp())) {
                nodep->v3warn(CONSTRAINTIGN,
                              "Unsupported: Array reduction constraint on array selected from a "
                              "non-fixed-size array or by a random index, treating as state");
                nodep->user1(false);
                if (editFormat(nodep)) return;
                nodep->v3fatalSrc("Method not handled in constraints? " << nodep);
                return;
            }
            // Without 'with', a dynamic subarray or member array (V3Width expands fixed-size
            // ones) is reduced like 'with (item)'; only an array variable is registered whole
            const bool perElem = withp || !VN_IS(nodep->fromp(), VarRef);

            // Create loop variable and header
            AstVar* const loopVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, "__Vreduce", nodep->findIntDType()};
            AstForeachHeader* const headerp
                = new AstForeachHeader{fl, nodep->fromp()->cloneTreePure(false), loopVarp};

            gateOnCurrentSize(nodep->fromp());

            // Determine SMT operation and its identity element, of the result's width (that of
            // the 'with' expression or, without one, of an array element)
            const char* smtOp = nullptr;
            std::string identity;
            const int width = nodep->dtypep()->width();
            if (nodep->method() == VCMethod::ARRAY_R_SUM) {
                smtOp = "bvadd";
                identity = "#b" + std::string(width, '0');
            } else if (nodep->method() == VCMethod::ARRAY_R_PRODUCT) {
                smtOp = "bvmul";
                identity = "#b" + std::string(width - 1, '0') + "1";
            } else if (nodep->method() == VCMethod::ARRAY_R_AND) {
                smtOp = "bvand";
                identity = "#b" + std::string(width, '1');
            } else if (nodep->method() == VCMethod::ARRAY_R_OR) {
                smtOp = "bvor";
                identity = "#b" + std::string(width, '0');
            } else {  // ARRAY_R_XOR
                smtOp = "bvxor";
                identity = "#b" + std::string(width, '0');
            }

            // Build loop body based on whether the reduction is per element
            AstCStmt* const cstmtp = new AstCStmt{fl};
            if (perElem) {
                // Per element: evaluate the 'with' expression or the element
                // The loop variable is the declared index, ArraySel and the lambda's index
                // argument use the storage index
                AstNodeExpr* idxRefp = new AstVarRef{fl, loopVarp, VAccess::READ};
                const AstUnpackArrayDType* const unpackp
                    = VN_CAST(nodep->fromp()->dtypep()->skipRefp(), UnpackArrayDType);
                if (unpackp && unpackp->lo()) {
                    idxRefp = new AstSub{fl, idxRefp,
                                         new AstConst{fl, AstConst::WidthedValue{}, 32,
                                                      static_cast<uint32_t>(unpackp->lo())}};
                    idxRefp->dtypeSetInt();
                }
                AstNodeExpr* const elemSelp = newSel(fl, nodep->fromp(), idxRefp);

                AstNode* perElemExprp = withp ? withp->exprp()->cloneTreePure(false)
                                              : elemSelp->cloneTreePure(false);
                if (AstLambdaArgRef* const rootRefp = VN_CAST(perElemExprp, LambdaArgRef)) {
                    if (rootRefp->index()) {
                        // item.index at root -> replace with storage index, adjust width
                        perElemExprp
                            = adjustWidth(fl, idxRefp->cloneTree(false), rootRefp->width(),
                                          rootRefp->dtypep()->numeric());
                    } else {
                        // item at root -> replace with array element
                        perElemExprp = elemSelp->cloneTreePure(false);
                    }
                    VL_DO_DANGLING(rootRefp->deleteTree(), rootRefp);
                } else {
                    // Arguments of a nested reduction's 'with' are left to that reduction
                    std::unordered_set<const AstLambdaArgRef*> nestedArgRefs;
                    perElemExprp->foreach([&](const AstWith* nestedp) {
                        nestedp->foreach([&](const AstLambdaArgRef* refp) {
                            if (refp->name() == nestedp->valueArgRefp()->name()
                                || refp->name() == nestedp->indexArgRefp()->name()) {
                                nestedArgRefs.insert(refp);
                            }
                        });
                    });
                    perElemExprp->foreach([&](AstLambdaArgRef* refp) {
                        if (nestedArgRefs.count(refp)) return;
                        if (refp->index()) {
                            // item.index -> replace with storage index, adjust to the
                            // index width the parent expression was sized for
                            AstNode* const replacementp
                                = adjustWidth(fl, idxRefp->cloneTree(false), refp->width(),
                                              refp->dtypep()->numeric());
                            refp->replaceWith(replacementp);
                        } else {
                            // item -> replace with array element
                            refp->replaceWith(elemSelp->cloneTreePure(false));
                        }
                        VL_DO_DANGLING(pushDeletep(refp), refp);
                    });
                }
                VL_DO_DANGLING(elemSelp->deleteTree(), elemSelp);

                // enum-literal folding pass already ran -- re-fold the literals.
                perElemExprp = V3Const::constifyEdit(perElemExprp);

                markRandDependent(perElemExprp);

                cstmtp->add("ret = \"(" + std::string(smtOp) + " \" + ret + \" \";\n");
                cstmtp->add("ret += ");
                cstmtp->add(iterateSubtreeReturnEdits(perElemExprp));
                cstmtp->add(";\n");
                cstmtp->add("ret += \")\";\n");
            } else {
                // Whole array variable: register each element as solver variable
                AstVarRef* const arrRefp = VN_CAST(nodep->fromp(), VarRef);
                AstVar* const arrVarp = arrRefp->varp();
                const std::string smtArrayName = arrVarp->name();
                AstNodeDType* const elemDtp = arrVarp->dtypep()->skipRefp()->subDTypep();
                const int elemWidth = elemDtp->width();
                AstNodeModule* const arrModulep = VN_AS(arrVarp->user2p(), NodeModule);
                AstNodeModule* const genModulep = VN_AS(m_genp->user2p(), NodeModule);
                arrVarp->user3(true);

                // Add write_var call to init task
                AstNodeExpr* const arrVarNamep
                    = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + smtArrayName + "\"", elemWidth};
                AstCMethodHard* const writeVarCallp
                    = new AstCMethodHard{fl, new AstVarRef{fl, genModulep, m_genp, VAccess::READ},
                                         VCMethod::RANDOMIZER_WRITE_VAR};
                writeVarCallp->addPinsp(new AstVarRef{fl, arrModulep, arrVarp, VAccess::READ});
                writeVarCallp->addPinsp(
                    new AstConst{fl, AstConst::Unsized64{}, static_cast<uint64_t>(elemWidth)});
                writeVarCallp->addPinsp(arrVarNamep);
                const uint32_t unpackedDims = arrVarp->dtypep()->dimensions(false).second;
                UASSERT_OBJ(unpackedDims == 1, arrVarp, "Array isn't 1-D");
                writeVarCallp->addPinsp(new AstConst{fl, 1});  // Dimension

                const RandomizeMode randMode = {.asUQuad = arrVarp->user1()};
                if (randMode.usesMode) {
                    writeVarCallp->addPinsp(
                        new AstConst{fl, AstConst::Unsized64{}, randMode.index});
                }
                writeVarCallp->dtypeSetVoid();
                AstBegin* initp = m_inlineInitBlockp;
                if (!initp) {
                    AstNodeFTask* const taskp
                        = VN_AS(m_memberMap.findMember(arrModulep, "new"), NodeFTask);
                    UASSERT_OBJ(taskp, arrModulep, "No new() in class");
                    initp = newInitBlockp(taskp);
                }
                initp->addStmtsp(writeVarCallp->makeStmt());

                // Create solver constraints
                AstSFormatF* const idxFormatp = new AstSFormatF{
                    fl, "#x%08x", false, new AstVarRef{fl, loopVarp, VAccess::READ}};
                iterateChildren(nodep);
                AstSFormatF* const varNamep
                    = createSolverArrDerefp(fl, nodep->fromp()->unlinkFrBack(), idxFormatp);

                cstmtp->add("ret += \" \";\n");
                cstmtp->add("ret += ");
                cstmtp->add(varNamep);
                cstmtp->add(";\n");
            }

            // Build final expression
            if (perElem) {
                // Per element: use lambda expression with AstCExpr
                AstCExpr* const cexprp = new AstCExpr{fl};
                cexprp->dtypeSetString();
                cexprp->add("([&]{\nstd::string ret = \"" + identity + "\";\n");
                cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                                         new AstForeach{fl, headerp, cstmtp}, true});
                cexprp->add("return ret;\n})()");
                nodep->replaceWith(new AstSFormatF{fl, "%s", false, cexprp});
            } else {
                // Whole array variable: use AstCExpr with conditional
                AstCExpr* const cexprp = new AstCExpr{fl};
                cexprp->dtypeSetString();
                cexprp->add("([&]{\nstd::string ret;\n");
                cexprp->add(new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                                         new AstForeach{fl, headerp, cstmtp}, true});
                cexprp->add("return ret.empty() ? \"" + identity + "\" : \"(" + smtOp
                            + "\" + ret + \")\";\n})()");
                nodep->replaceWith(new AstSFormatF{fl, "%s", false, cexprp});
            }
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }

        // We've handled DYN_SIZE already if they should be randomized
        if (nodep->method() == VCMethod::DYN_SIZE || nodep->method() == VCMethod::ASSOC_SIZE) {
            AstNodeExpr* nodeExprp = nodep->fromp();
            // Check if it is a pure chain of MemberSel ended with VarRef
            // if not throw warning
            while (VN_IS(nodeExprp, MemberSel)) {
                nodeExprp = VN_AS(nodeExprp, MemberSel)->fromp();
            }
            if (VN_IS(nodeExprp, VarRef)) {
                nodep->replaceWith(getConstFormat(nodep->cloneTreePure(false)));
                VL_DO_DANGLING(nodep->deleteTree(), nodep);
                return;
            }
        }

        nodep->v3warn(CONSTRAINTIGN,
                      "Unsupported: randomizing this expression, treating as state");
        nodep->user1(false);

        if (editFormat(nodep)) return;
        nodep->v3fatalSrc("Method not handled in constraints? " << nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override {
        if (editFormat(nodep)) return;

        AstFunc* const funcp = VN_CAST(nodep->taskp(), Func);
        if (!funcp) {
            // Tasks have no return value and can't appear in expressions.
            // Parser rejects this, so reaching here indicates a compiler bug.
            nodep->v3fatalSrc("Unexpected task call in constraint expression");
            return;
        }

        AstNodeExpr* const retExprp = extractReturnExpr(nodep, funcp);
        if (!retExprp) {
            // IEEE 1800-2023 18.5.11: The random arguments are solved before the constraint,
            // which then uses the call's result as state
            if (!addFuncArgVars(nodep)) {
                nodep->v3warn(CONSTRAINTIGN,
                              "Unsupported: function argument in constraint using a random "
                              "variable of non-integral type, treating as state");
            }
            nodep->user1(false);
            editFormat(nodep);
            return;
        }

        // Map formal parameters to actual arguments using V3Task infrastructure
        const V3TaskConnects tconnects
            = V3Task::taskConnects(nodep, funcp->stmtsp(), nullptr, false);

        // Clone return expression, substitute params with args.
        // Track the root via a local pointer: when the root itself is a VarRef to a port
        // (e.g. body `F = d;`), the cloned root has no back pointer, so foreach's
        // replaceWith would trip the "no back" assertion -- substitute the root pointer
        // directly instead.
        AstNodeExpr* inlinedp = retExprp->cloneTreePure(false);
        for (const auto& tconnect : tconnects) {
            const AstVar* const portp = tconnect.first;
            AstArg* const argp = tconnect.second;
            if (!argp || !argp->exprp()) continue;
            if (AstVarRef* const rootRefp = VN_CAST(inlinedp, VarRef)) {
                if (rootRefp->varp() == portp) {
                    inlinedp = argp->exprp()->cloneTreePure(false);
                    VL_DO_DANGLING(rootRefp->deleteTree(), rootRefp);
                    continue;
                }
            }
            inlinedp->foreach([&](AstVarRef* refp) {
                if (refp->varp() == portp) {
                    refp->replaceWith(argp->exprp()->cloneTreePure(false));
                    VL_DO_DANGLING(refp->deleteTree(), refp);
                }
            });
        }

        inlinedp->dtypep(nodep->dtypep());
        propagateUser1InlineRecurse(inlinedp);
        nodep->replaceWith(inlinedp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        iterate(inlinedp);
    }
    // Skip non-constraint stmts appended to the iterating list during inline randomize-with
    void visit(AstNodeStmt* nodep) override {}
    void visit(AstNodeExpr* nodep) override {
        if (editFormat(nodep)) return;
        nodep->v3fatalSrc(
            "Visit function missing? Constraint function missing for math node: " << nodep);
    }
    void visit(AstNode* nodep) override {
        nodep->v3fatalSrc(
            "Visit function missing? Constraint function missing for node: " << nodep);
    }

    // Build the runtime statement that calls RANDOMIZER_DISABLE_SOFT on the
    // variable referenced by the given AstConstraintExpr.  Parser enforces
    // constraint_primary operand (verilog.y, IEEE 1800-2023 18.5.13).
    AstNode* buildDisableSoftCallStmt(AstConstraintExpr* nodep) {
        std::string varName;
        if (const AstNodeVarRef* const vrefp = VN_CAST(nodep->exprp(), NodeVarRef)) {
            varName = vrefp->name();
        } else if (const AstMemberSel* const mselp = VN_CAST(nodep->exprp(), MemberSel)) {
            varName = mselp->name();
        } else {
            nodep->v3fatalSrc("Unexpected expression type in disable soft");
        }
        AstCMethodHard* const callp = new AstCMethodHard{
            nodep->fileline(),
            new AstVarRef{nodep->fileline(), VN_AS(m_genp->user2p(), NodeModule), m_genp,
                          VAccess::READWRITE},
            VCMethod::RANDOMIZER_DISABLE_SOFT,
            new AstConst{nodep->fileline(), AstConst::String{}, varName}};
        callp->dtypeSetVoid();
        return callp->makeStmt();
    }

    // Pre-pass: for every AstConstraintExpr(isDisableSoft) nested inside an
    // AstConstraintIf subtree (any depth), return a list of runtime AstIf
    // statements `if (accumulated_cond) randomizer.disable_soft(var);` where
    // accumulated_cond AND-folds the enclosing then/else branch conditions.
    // The original ConstraintExpr is replaced with `1'b1` so editSingle()
    // folds the surrounding boolean cleanly.  Caller appends the returned
    // list to the constraint-items chain; that chain becomes the setup task
    // body, which runs before the solver on every randomize() call -- giving
    // disable-soft real conditional semantics per IEEE 1800-2023 18.5.13.
    AstNode* extractConditionalDisableSofts(AstNode* itemsp, AstNodeExpr* outerCondp) {
        AstNode* hoistListp = nullptr;
        for (AstNode *stmtp = itemsp, *nextp; stmtp; stmtp = nextp) {
            nextp = stmtp->nextp();
            if (AstConstraintIf* const ifp = VN_CAST(stmtp, ConstraintIf)) {
                // then branch: accumulated = outer && this.cond
                AstNodeExpr* const thenCondp
                    = newGuardAnd(outerCondp, ifp->condp()->cloneTree(false));
                if (AstNode* const thenHoistp
                    = extractConditionalDisableSofts(ifp->thensp(), thenCondp)) {
                    hoistListp
                        = hoistListp ? AstNode::addNext(hoistListp, thenHoistp) : thenHoistp;
                }
                VL_DO_DANGLING(thenCondp->deleteTree(), thenCondp);
                if (ifp->elsesp()) {
                    // else branch: accumulated = outer && !this.cond
                    AstNodeExpr* const elseCondp = newGuardAnd(outerCondp, newNotCond(ifp));
                    if (AstNode* const elseHoistp
                        = extractConditionalDisableSofts(ifp->elsesp(), elseCondp)) {
                        hoistListp
                            = hoistListp ? AstNode::addNext(hoistListp, elseHoistp) : elseHoistp;
                    }
                    VL_DO_DANGLING(elseCondp->deleteTree(), elseCondp);
                }
            } else if (AstConstraintExpr* const exprp = VN_CAST(stmtp, ConstraintExpr)) {
                if (exprp->isDisableSoft() && outerCondp) {
                    FileLine* const fl = exprp->fileline();
                    AstIf* const hoistIfp = new AstIf{fl, outerCondp->cloneTreePure(false),
                                                      buildDisableSoftCallStmt(exprp), nullptr};
                    hoistListp = hoistListp ? AstNode::addNext(hoistListp,
                                                               static_cast<AstNode*>(hoistIfp))
                                            : static_cast<AstNode*>(hoistIfp);
                    // Replace in-tree disable-soft with a no-op boolean
                    // constraint so editSingle() folds cleanly.
                    AstConstraintExpr* const truep
                        = new AstConstraintExpr{fl, new AstConst{fl, AstConst::BitTrue{}}};
                    exprp->replaceWith(truep);
                    VL_DO_DANGLING(exprp->deleteTree(), exprp);
                }
            }
            // foreach/unique bodies are left untouched: disable-soft inside
            // a foreach would need per-iteration condition support, and
            // unique cannot legally contain disable-soft.
        }
        return hoistListp;
    }

public:
    // CONSTRUCTORS
    explicit ConstraintExprVisitor(AstClass* classp, VMemberMap& memberMap, AstNode* nodep,
                                   AstBegin* inlineInitp, AstVar* genp, AstVar* randModeVarp,
                                   std::set<std::string>& writtenVars,
                                   uint32_t* uniqueConstraintIdp, V3UniqueNames& uniqueNames,
                                   AstNodeFTask* memberselInitTaskp = nullptr,
                                   VInsertionSet<AstVar*>* sizeConstrainedArraysp = nullptr,
                                   AstNodeFTask* prepareConstrainedArraysp = nullptr,
                                   std::set<const AstVar*>* newWrittenVarsp = nullptr)
        : m_classp{classp}
        , m_inlineInitBlockp{inlineInitp}
        , m_memberselInitTaskp{memberselInitTaskp}
        , m_genp{genp}
        , m_randModeVarp{randModeVarp}
        , m_memberMap{memberMap}
        , m_writtenVars{writtenVars}
        , m_newWrittenVarsp{newWrittenVarsp}
        , m_sizeConstrainedArraysp{sizeConstrainedArraysp}
        , m_prepareConstrainedArraysp{prepareConstrainedArraysp}
        , m_uniqueConstraintIdp{uniqueConstraintIdp}
        , m_uniqueNames{uniqueNames} {
        // Pre-pass before SMT lowering: extract conditional disable-soft
        // directives as runtime AstIf statements and append them to the
        // constraint-items chain so they reach the setup task body.  The SMT
        // visitor skips these via visit(AstIf) above.
        if (AstNode* const hoistListp
            = nodep ? extractConditionalDisableSofts(nodep, nullptr) : nullptr) {
            nodep->addNext(hoistListp);
        }
        iterateAndNextNull(nodep);
    }
    // Constraint items calling functions with random arguments
    const std::vector<ConstraintFuncCall>& funcCalls() const { return m_funcCalls; }
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
    //  AstConstraint::user2p() -> AstTask*. Pointer to constraint setup procedure
    //  AstClass::user2p()      -> AstVar*.  Rand mode state variable
    //  AstVar::user3()         -> bool. Handled in constraints
    //  AstClass::user3p()      -> AstVar*.  Constrained randomizer variable
    //  AstConstraint::user3p() -> AstTask*. Pointer to resize procedure
    //  AstConstraintForeach::user3p() -> AstNode*. Dist bucket preamble stmts (foreach case)
    //  AstClass::user4p()      -> AstVar*.  Constraint mode state variable
    //  AstVar::user4p()        -> AstVar*.  Size variable for constrained queues
    //  AstNodeFTaskRef::user4() -> bool.  Processed
    //  AstMemberSel::user2p()  -> AstNodeModule*. Pointer to containing module
    // VNUser1InUse    m_inuser1;      (Allocated for use in RandomizeMarkVisitor)
    // VNUser2InUse    m_inuser2;      (Allocated for use in RandomizeMarkVisitor)
    const VNUser3InUse m_inuser3;
    const VNUser4InUse m_inuser4;

    // STATE
    V3UniqueNames m_inlineUniqueNames;  // For generating unique function names
    const ClonedConstraints& m_cloneObjps;  // Constraints cloned from objects
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
    AstAssocArrayDType* m_elemModeDtp = nullptr;  // Type of per-element rand mode state
    const std::unordered_set<AstVar*>& m_elemModeArrays;  // Arrays with per-element rand_mode()
    std::unordered_map<const AstVar*, AstVar*> m_elemModeVars;  // Array -> its element modes
    std::unordered_set<const AstClass*> m_elemModePinPath;  // Classes newClassElemModePinsp is in
    int m_randCaseNum = 0;  // Randcase number within a module for var naming
    int m_distNum = 0;  // Dist bucket variable counter within a module for var naming
    std::map<std::string, AstCDType*> m_randcDtypes;  // RandC data type deduplication
    AstConstraint* m_constraintp = nullptr;  // Current constraint
    std::set<std::string> m_constraintSizedArrays;  // SMT names of arrays m_constraintp sizes
    std::unordered_set<const AstClass*> m_visitedClasses;  // Classes visited so far
    std::set<std::string> m_writtenVars;  // Track write_var calls per class to avoid duplicates
    // m_writtenVars of each class, with those of its base classes
    std::map<const AstClass*, std::set<std::string>> m_classWrittenVars;
    // Classes whose randomization may randomize a randc variable
    std::unordered_set<const AstClass*> m_randcClasses;
    std::map<AstClass*, VInsertionSet<AstVar*>> m_sizeConstrainedArrays;  // Per-class arrays
    std::map<const AstVar*, AstVar*> m_memberSizeVars;  // Size variables of member arrays
    // Arrays of member objects, by SMT name, each with its member select
    using MemberArrays = std::map<std::string, const AstMemberSel*>;
    std::map<AstClass*, AstVar*>
        m_staticConstraintModeVars;  // Static constraint mode vars per class
    std::map<AstClass*, std::pair<bool, bool>>
        m_prePostWrap;  // Per-handle-type pre/post virtual wrapper presence
    uint32_t m_uniqueConstraintId = 0;  // current ID of unique call
    // Methods implementing randomize(null), see addRandomizeNullBody
    enum class NullPhase : uint8_t { NONE, ENTRY, PRE, CHECK, POST };
    std::vector<std::tuple<AstClass*, NullPhase, AstFunc*>>
        m_randomizeNullFuncs;  // randomize(null) methods, body added after lowering
    std::map<AstClass*, std::vector<AstClass*>> m_derivedClasses;  // Directly derived classes
    NullPhase m_nullPhase = NullPhase::NONE;  // Building a randomize(null) method
    std::map<const AstConstraint*, std::vector<ConstraintFuncCall>>
        m_constraintFuncCalls;  // Items of each constraint calling functions with random args
    std::unordered_set<const AstClass*> m_globalOwnerClassps;  // Classes solving sub-objects
    std::set<const AstVar*> m_newWrittenVars;  // Variables registered in new() of their class

    // METHODS
    // Expand unique{a,b,c} with explicit elements into pairwise != constraints.
    // Whole-array unique{arr} is left for ConstraintExprVisitor's rand_unique handling.
    // Recurses into conditional and foreach bodies, so that the pairwise
    // constraints stay under the guard they were written under.
    static void expandUniqueElementList(AstNode* itemsp) {
        AstNode* itemp = itemsp;
        while (itemp) {
            AstNode* const nextp = itemp->nextp();
            if (const AstConstraintIf* const ifp = VN_CAST(itemp, ConstraintIf)) {
                expandUniqueElementList(ifp->thensp());
                expandUniqueElementList(ifp->elsesp());
                itemp = nextp;
                continue;
            }
            if (const AstConstraintForeach* const foreachp = VN_CAST(itemp, ConstraintForeach)) {
                expandUniqueElementList(foreachp->bodyp());
                itemp = nextp;
                continue;
            }
            AstConstraintUnique* const uniquep = VN_CAST(itemp, ConstraintUnique);
            if (!uniquep) {
                itemp = nextp;
                continue;
            }

            std::vector<AstNodeExpr*> exprItems;
            bool hasArrayVarRef = false;
            for (AstNode* const rp : uniquep->rangespList()) {
                // A container's elements are made distinct by rand_unique, not pairwise
                const AstNodeDType* const dtypep = VN_AS(rp, NodeExpr)->dtypep()->skipRefp();
                if (VN_IS(dtypep, NodeArrayDType) || VN_IS(dtypep, QueueDType)
                    || VN_IS(dtypep, DynArrayDType) || VN_IS(dtypep, AssocArrayDType)
                    || VN_IS(dtypep, WildcardArrayDType)) {
                    hasArrayVarRef = true;
                    continue;
                }
                exprItems.push_back(VN_AS(rp, NodeExpr));
            }

            if (exprItems.size() >= 2) {
                FileLine* const fl = uniquep->fileline();
                for (size_t i = 0; i < exprItems.size(); i++) {
                    for (size_t j = i + 1; j < exprItems.size(); j++) {
                        AstNodeExpr* const lhsp = exprItems[i]->cloneTree(false);
                        AstNodeExpr* const rhsp = exprItems[j]->cloneTree(false);
                        AstNeq* const neqp = new AstNeq{fl, lhsp, rhsp};
                        neqp->user1(true);
                        AstConstraintExpr* const cexprp = new AstConstraintExpr{fl, neqp};
                        uniquep->addNextHere(cexprp);
                    }
                }
                if (!hasArrayVarRef) {
                    uniquep->unlinkFrBack();
                    VL_DO_DANGLING(uniquep->deleteTree(), uniquep);
                }
            } else if (exprItems.size() == 1 && !hasArrayVarRef) {
                // A set of one element is unique whatever that element holds
                uniquep->unlinkFrBack();
                VL_DO_DANGLING(uniquep->deleteTree(), uniquep);
            }
            itemp = nextp;
        }
    }
    void createRandomGenerator(AstClass* const classp) {
        if (classp->user3p()) return;
        if (classp->extendsp()) {
            createRandomGenerator(classp->extendsp()->classp());
            return;
        }
        AstVar* const genp = new AstVar{classp->fileline(), VVarType::MEMBER, "constraint",
                                        classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)};
        genp->user2p(classp);
        classp->addMembersp(genp);
        classp->user3p(genp);
    }
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
    // Return statements randomizing an std::randomize() argument without constraints
    AstNodeStmt* newBasicStdRandStmtsp(FileLine* const fl, AstVar* const stdrandp,
                                       AstVar* const fvarp, AstNodeExpr* const exprp) {
        AstNodeDType* const dtypep = exprp->dtypep()->skipRefp();
        const AstStructDType* const structp = VN_CAST(arrayElementDTypep(dtypep), StructDType);
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
        const uint64_t width = arrayElementDTypep(dtypep)->width();
        callp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, width});
        callp->dtypeSetBit();
        return new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE},
                             new AstAnd{fl, new AstVarRef{fl, fvarp, VAccess::READ}, callp}};
    }
    AstTask* createPrepareConstrainedArraysTask(AstClass* const classp) {
        static const char* const name = "__Vprepare_constrained_arrays";
        AstTask* const taskp = new AstTask{classp->fileline(), name, nullptr};
        taskp->classMethod(true);
        classp->addMembersp(taskp);
        m_memberMap.insert(classp, taskp);
        return taskp;
    }
    AstTask* getCreateAggrResizeTask(AstClass* const classp) {
        static constexpr const char* const name = "__Vresize_constrained_arrays";
        AstTask* resizeTaskp = VN_AS(m_memberMap.findMember(classp, name), Task);
        if (resizeTaskp) return resizeTaskp;
        resizeTaskp = new AstTask{classp->fileline(), name, nullptr};
        resizeTaskp->classMethod(true);
        resizeTaskp->isVirtual(true);
        classp->addMembersp(resizeTaskp);
        m_memberMap.insert(classp, resizeTaskp);
        return resizeTaskp;
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
        if (classp->user4p()) return VN_AS(classp->user4p(), Var);
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getConstraintModeVar(extendsp->classp());
        }
        return nullptr;
    }
    AstVar* getCreateStaticConstraintModeVar(AstClass* const classp) {
        auto it = m_staticConstraintModeVars.find(classp);
        if (it != m_staticConstraintModeVars.end()) return it->second;
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getCreateStaticConstraintModeVar(extendsp->classp());
        }
        AstVar* const staticModeVarp = createStaticModeVar(classp, "__Vstaticconstraintmode");
        m_staticConstraintModeVars[classp] = staticModeVarp;
        return staticModeVarp;
    }
    AstVar* getStaticConstraintModeVar(AstClass* const classp) {
        auto it = m_staticConstraintModeVars.find(classp);
        if (it != m_staticConstraintModeVars.end()) return it->second;
        if (AstClassExtends* const extendsp = classp->extendsp()) {
            return getStaticConstraintModeVar(extendsp->classp());
        }
        return nullptr;
    }
    AstVar* getCreateStaticRandModeVar(AstClass* const classp) {
        if (AstVar* const varp = getStaticRandModeVar(classp)) return varp;
        return createStaticModeVar(classp->baseMostClassp(), "__Vstaticrandmode");
    }
    AstVar* getStaticRandModeVar(AstClass* const classp) {
        return findStaticRandModeVar(m_memberMap, classp);
    }
    // Get or create the per-element rand_mode state of an array, nullptr if it has none
    AstVar* elemModeVarp(AstVar* const arrVarp) {
        if (!m_elemModeArrays.count(arrVarp)) return nullptr;
        AstVar*& modeVarp = m_elemModeVars[arrVarp];
        if (modeVarp) return modeVarp;
        // Keyed by element offset, kept across resizes, holding 1 for the elements with
        // rand_mode off
        FileLine* const fl = arrVarp->fileline();
        if (!m_elemModeDtp) {
            m_elemModeDtp
                = new AstAssocArrayDType{fl, arrVarp->findBitDType(), arrVarp->findUInt32DType()};
            m_elemModeDtp->dtypep(m_elemModeDtp);
            v3Global.rootp()->typeTablep()->addTypesp(m_elemModeDtp);
        }
        AstClass* const classp = VN_AS(arrVarp->user2p(), Class);
        modeVarp
            = new AstVar{fl, VVarType::MEMBER, "__Vrandmode__" + arrVarp->name(), m_elemModeDtp};
        modeVarp->user2p(classp);
        classp->addMembersp(modeVarp);
        return modeVarp;
    }
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
    static void addSetRandMode(AstNodeFTask* const ftaskp, AstVar* const genp,
                               AstVar* const randModeVarp) {
        FileLine* const fl = ftaskp->fileline();
        AstCMethodHard* const setRandModep = new AstCMethodHard{
            fl, new AstVarRef{fl, VN_AS(genp->user2p(), NodeModule), genp, VAccess::WRITE},
            VCMethod::CLASS_SET_RANDMODE,
            new AstVarRef{fl, VN_AS(randModeVarp->user2p(), NodeModule), randModeVarp,
                          VAccess::READ}};
        setRandModep->dtypeSetVoid();
        ftaskp->addStmtsp(setRandModep->makeStmt());
    }
    static void addSetStaticRandMode(AstNodeFTask* const ftaskp, AstVar* const genp,
                                     AstVar* const staticRandModeVarp) {
        FileLine* const fl = ftaskp->fileline();
        AstCMethodHard* const setp = new AstCMethodHard{
            fl, new AstVarRef{fl, VN_AS(genp->user2p(), NodeModule), genp, VAccess::WRITE},
            VCMethod::RANDOMIZER_SET_STATIC_RANDMODE,
            new AstVarRef{fl, VN_AS(staticRandModeVarp->user2p(), NodeModule), staticRandModeVarp,
                          VAccess::READ}};
        setp->dtypeSetVoid();
        ftaskp->addStmtsp(setp->makeStmt());
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
            if (hasConstraints) createRandomGenerator(classp);
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
        AstVar* const staticRandModeVarp = getStaticRandModeVar(rootp);
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
                                                             : getRandModeVarFromClass(classp);
        return VN_AS(wrapIfMode(rmode, modeVarp, stmtp), NodeStmt);
    }
    // Whether the array element at indexp has rand_mode off, given the array's modesp
    static AstNodeExpr* newElemModeOffp(AstNodeExpr* const modesp, AstNodeExpr* const indexp) {
        AstCMethodHard* const atp = new AstCMethodHard{
            indexp->fileline(), modesp, VCMethod::ARRAY_AT, indexp->cloneTree(false)};
        atp->dtypeSetBit();
        return atp;
    }
    // Read reference to member varp of objp, or of 'this' if objp is nullptr
    static AstNodeExpr* newMemberRefp(FileLine* const fl, AstNodeExpr* const objp,
                                      AstVar* const varp) {
        if (objp) return new AstMemberSel{fl, objp->cloneTreePure(false), varp};
        return new AstVarRef{fl, VN_AS(varp->user2p(), Class), varp, VAccess::READ};
    }
    // Element at offset offsetp of array arrVarp of objp, or of 'this' if objp is nullptr
    static AstNodeExpr* newElemp(FileLine* const fl, AstNodeExpr* const objp,
                                 AstVar* const arrVarp, AstNodeExpr* const offsetp) {
        AstNodeExpr* const arrp = newMemberRefp(fl, objp, arrVarp);
        AstNodeExpr* const elemp
            = VN_IS(arrVarp->dtypep()->skipRefp(), UnpackArrayDType)
                  ? static_cast<AstNodeExpr*>(new AstArraySel{fl, arrp, offsetp})
                  : new AstCMethodHard{fl, arrp, VCMethod::ARRAY_AT, offsetp};
        elemp->dtypep(arrVarp->dtypep()->skipRefp()->subDTypep());
        return elemp;
    }
    // Skip the elements without a randomized object in a constraint cloned for an array
    void skipInactiveElems(AstConstraint* const constrp) {
        // A null element has no object (IEEE 1800-2023 18.4), and the object of an element
        // with rand_mode off is not randomized (18.8), so their constraints do not apply. Such a
        // clone is a foreach over the array, already lowered to setup statements, which are
        // skipped for those elements.
        const auto it = m_cloneObjps.find(constrp);
        if (it == m_cloneObjps.end()) return;
        AstMemberSel* const selp = VN_CAST(it->second.objp, MemberSel);
        AstVar* const arrVarp = selp ? selp->varp() : VN_AS(it->second.objp, VarRef)->varp();
        if (VN_IS(arrVarp->dtypep()->skipRefp(), ClassRefDType)) return;  // Cloned for an object
        AstNodeExpr* const objp = selp ? selp->fromp() : nullptr;
        AstForeach* const foreachp = VN_AS(VN_AS(constrp->itemsp(), Begin)->stmtsp(), Foreach);
        FileLine* const fl = foreachp->fileline();
        std::vector<AstVar*> idxVarps;
        for (AstNode* nodep = foreachp->headerp()->elementsp(); nodep; nodep = nodep->nextp()) {
            idxVarps.push_back(VN_AS(nodep, Var));
        }
        AstNodeExpr* const elemp = newElemSelp(fl, newMemberRefp(fl, objp, arrVarp), idxVarps);
        AstNodeExpr* condp
            = new AstNeq{fl, elemp->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
        if (AstVar* const modeVarp = elemModeVarp(arrVarp)) {
            // Only the elements of a one-dimensional array have their own rand_mode()
            AstNodeExpr* const offsetp = newElemOffsetp(
                fl, arrVarp->dtypep(), new AstVarRef{fl, idxVarps[0], VAccess::READ});
            condp = new AstLogAnd{
                fl, condp,
                new AstNot{fl, newElemModeOffp(newMemberRefp(fl, objp, modeVarp), offsetp)}};
            VL_DO_DANGLING(offsetp->deleteTree(), offsetp);
        }
        if (AstNodeExpr* const modep = newObjConstraintModep(elemp, it->second.origp)) {
            condp = new AstLogAnd{fl, condp, modep};
        }
        VL_DO_DANGLING(elemp->deleteTree(), elemp);
        AstNode* const bodyp = foreachp->bodyp()->unlinkFrBackWithNext();
        foreachp->addBodyp(new AstIf{fl, condp, bodyp});
    }
    // Statements making the solver keep the array's elements with rand_mode off unchanged
    AstNodeStmt* newElemModePinsp(AstVar* const arrVarp, AstVar* const modeVarp,
                                  AstVar* const genp, AstNodeExpr* const objp,
                                  const std::string& prefix) {
        FileLine* const fl = arrVarp->fileline();
        const std::string name = prefix + arrVarp->name();
        AstVar* const idxVarp = new AstVar{fl, VVarType::VAR, m_randArrayUniqueNames.get(""),
                                           arrVarp->findUInt32DType()};
        // Offset of the element, as used by the solver
        AstNodeExpr* const offsetp
            = newElemOffsetp(fl, arrVarp->dtypep(), new AstVarRef{fl, idxVarp, VAccess::READ});
        AstNodeExpr* const elemp = newElemp(fl, objp, arrVarp, offsetp->cloneTree(false));
        const bool unpacked = VN_IS(arrVarp->dtypep()->skipRefp(), UnpackArrayDType);
        // Pin solver term termFmt (formatted with the offset) of variable varFmt to valuep
        const auto newPinp = [&](const std::string& varFmt, const std::string& termFmt,
                                 AstNodeExpr* valuep) {
            AstCMethodHard* const pinp = new AstCMethodHard{
                fl, new AstVarRef{fl, VN_AS(genp->user2p(), NodeModule), genp, VAccess::READWRITE},
                VCMethod::RANDOMIZER_PIN_FROZEN,
                new AstSFormatF{fl, varFmt, false,
                                varFmt == name ? nullptr : offsetp->cloneTree(false)}};
            pinp->addPinsp(new AstSFormatF{
                fl, "(__Vbv (= " + termFmt + " %s))", false,
                AstNode::addNext(offsetp->cloneTree(false), getConstFormat(valuep))});
            pinp->dtypeSetVoid();
            return pinp->makeStmt();
        };
        AstNodeStmt* pinsp = nullptr;
        if (const AstClassRefDType* const classRefp
            = VN_CAST(elemp->dtypep()->skipRefp(), ClassRefDType)) {
            // Each field registered by createWriteVarForClassFields
            const std::string elemFmt = name + "." + (unpacked ? "%0x" : "%8x") + ".";
            foreachSolverElemField(classRefp->classp(), [&](AstVar* const memberVarp) {
                const std::string fieldFmt = elemFmt + memberVarp->name();
                pinsp = AstNode::addNextNull(
                    pinsp, newPinp(fieldFmt, fieldFmt,
                                   new AstMemberSel{fl, elemp->cloneTree(false), memberVarp}));
            });
            pinsp
                = new AstIf{fl, new AstNeq{fl, elemp, new AstConst{fl, AstConst::Null{}}}, pinsp};
        } else {
            pinsp = newPinp(name, "(select " + name + " #x%8x)", elemp);
        }
        AstIf* const ifp
            = new AstIf{fl, newElemModeOffp(newMemberRefp(fl, objp, modeVarp), offsetp), pinsp};
        VL_DO_DANGLING(offsetp->deleteTree(), offsetp);
        // In a block, so the loop variable is moved out of an enclosing 'if'
        return new AstBegin{
            fl, m_uniqueNames.get("__VrandBlock"),
            new AstForeach{fl, new AstForeachHeader{fl, newMemberRefp(fl, objp, arrVarp), idxVarp},
                           ifp},
            false};
    }
    // Statements pinning the elements with rand_mode off in the arrays of classp
    AstNode* newClassElemModePinsp(AstClass* const classp, AstVar* const genp,
                                   AstNodeExpr* const objp = nullptr,
                                   const std::string& prefix = "") {
        // Also those of its rand objects, as their constraints may be solved together with
        // classp's (IEEE 1800-2023 18.5.9). objp reaches classp, nullptr for 'this', and
        // prefix is classp's solver variable name prefix.
        if (m_elemModeArrays.empty()) return nullptr;
        AstNode* stmtsp = nullptr;
        m_elemModePinPath.insert(classp);  // Against cycles of rand objects
        classp->foreachMember([&](AstClass*, AstVar* const varp) {
            if (AstVar* const modeVarp = elemModeVarp(varp)) {
                stmtsp = AstNode::addNextNull(
                    stmtsp, newElemModePinsp(varp, modeVarp, genp, objp, prefix));
            }
            if (!varp->isRand()) return;
            const AstClassRefDType* const classRefp
                = VN_CAST(varp->dtypep()->skipRefp(), ClassRefDType);
            if (!classRefp || m_elemModePinPath.count(classRefp->classp())) return;
            FileLine* const fl = varp->fileline();
            AstNodeExpr* const subObjp = newMemberRefp(fl, objp, varp);
            if (AstNode* const subStmtsp = newClassElemModePinsp(
                    classRefp->classp(), genp, subObjp, prefix + varp->name() + ".")) {
                stmtsp = AstNode::addNextNull(
                    stmtsp, new AstIf{fl,
                                      new AstNeq{fl, subObjp->cloneTree(false),
                                                 new AstConst{fl, AstConst::Null{}}},
                                      subStmtsp});
            }
            VL_DO_DANGLING(subObjp->deleteTree(), subObjp);
        });
        m_elemModePinPath.erase(classp);
        return stmtsp;
    }
    // Read of the constraint_mode() of constraint constrp of objp, nullptr if never set
    AstNodeExpr* newObjConstraintModep(AstNodeExpr* const objp, AstConstraint* const constrp) {
        const RandomizeMode mode = {.asUQuad = constrp->user1()};
        if (!mode.usesMode) return nullptr;
        FileLine* const fl = objp->fileline();
        AstClass* const classp = VN_AS(objp->dtypep()->skipRefp(), ClassRefDType)->classp();
        AstNodeExpr* modesp;
        if (constrp->isStatic()) {
            AstVar* const modeVarp = getStaticConstraintModeVar(classp);
            modesp = new AstVarRef{fl, VN_AS(modeVarp->user2p(), NodeModule), modeVarp,
                                   VAccess::READ};
        } else {
            AstVar* const modeVarp = getConstraintModeVar(classp);
            modesp = new AstMemberSel{fl, objp->cloneTree(false), modeVarp};
        }
        AstCMethodHard* const atp
            = new AstCMethodHard{fl, modesp, VCMethod::ARRAY_AT, new AstConst{fl, mode.index}};
        atp->dtypeSetUInt32();
        return atp;
    }
    AstNode* wrapIfConstraintMode(AstClass* classp, AstConstraint* const constrp, AstNode* stmtp) {
        const auto it = m_cloneObjps.find(constrp);
        if (it != m_cloneObjps.end()) {
            // The constraint of an object can be off in that object (IEEE 1800-2023 18.9), but
            // not in the object constraining it. skipInactiveElems checks the objects of an
            // array.
            AstNodeExpr* const objp = it->second.objp;
            if (!VN_IS(objp->dtypep()->skipRefp(), ClassRefDType)) return stmtp;
            AstNodeExpr* const modep = newObjConstraintModep(objp, it->second.origp);
            return modep ? new AstIf{stmtp->fileline(), modep, stmtp} : stmtp;
        }
        const RandomizeMode rmode = {.asUQuad = constrp->user1()};
        AstVar* const modeVarp = constrp->isStatic() ? getStaticConstraintModeVar(classp)
                                                     : getConstraintModeVar(classp);
        return wrapIfMode(rmode, modeVarp, stmtp);
    }
    static AstNode* wrapIfMode(const RandomizeMode mode, AstVar* modeVarp, AstNode* stmtp) {
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
                    fl, newElemModeOffp(newMemberRefp(fl, nullptr, elemModeVarp), firstIndexp)},
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
            // Each object of a cycle of rand handles is randomized once per call
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
        } else if (const AstPackArrayDType* const arrayDtp = VN_CAST(memberDtp, PackArrayDType);
                   arrayDtp && packedHasEnum(arrayDtp)) {
            // A loop over the elements, so each enum gets one of its values
            AstNodeDType* const elemDtp = arrayDtp->subDTypep();
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
                new AstLt{fl, new AstVarRef{fl, idxVarp, VAccess::READ},
                          new AstConst{fl, static_cast<uint32_t>(arrayDtp->elementsConst())}}});
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

        return new AstRandRNG{fl, dtypep};
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
                m_writtenVars.clear();
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
    AstTask* newSetupConstraintTask(AstClass* const nodep, const std::string& name) {
        AstTask* const taskp = new AstTask{nodep->fileline(), name + "_setup_constraint", nullptr};
        taskp->classMethod(true);
        nodep->addMembersp(taskp);
        return taskp;
    }
    AstTask* newResizeConstrainedArrayTask(AstClass* const nodep, const std::string& name) {
        AstTask* const taskp
            = new AstTask{nodep->fileline(), name + "_resize_constrained_array", nullptr};
        taskp->classMethod(true);
        nodep->addMembersp(taskp);
        return taskp;
    }
    AstNodeStmt* implementConstraintsClear(FileLine* const fileline, AstVar* const genp) {
        AstCMethodHard* const clearp = new AstCMethodHard{
            fileline,
            new AstVarRef{fileline, VN_AS(genp->user2p(), NodeModule), genp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_CLEARCONSTRAINTS};
        clearp->dtypeSetVoid();
        return clearp->makeStmt();
    }
    // Statement continuing the randc cycles of fromGenp in toGenp
    static AstNodeStmt* newRandcHistoryFromp(FileLine* const fl, AstVar* const toGenp,
                                             AstVar* const fromGenp) {
        AstCMethodHard* const callp = new AstCMethodHard{
            fl,
            new AstVarRef{fl, VN_CAST(toGenp->user2p(), NodeModule), toGenp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_RANDC_HISTORY_FROM,
            new AstVarRef{fl, VN_CAST(fromGenp->user2p(), NodeModule), fromGenp, VAccess::READ}};
        callp->dtypeSetVoid();
        return callp->makeStmt();
    }
    // Find m_randcClasses: the classes with a randc variable, and, from those, the classes with
    // a rand handle to one, or extending one
    void findRandcClasses(AstNetlist* const nodep) {
        // Classes with a rand handle to, or extending, each class
        std::unordered_map<const AstClass*, std::vector<const AstClass*>> reachingClasses;
        std::vector<const AstClass*> worklist;  // Classes found, whose reaching classes are next
        nodep->foreach([&](const AstClass* const classp) {
            if (classp->extendsp()) {
                reachingClasses[classp->extendsp()->classp()].push_back(classp);
            }
            for (const AstNode* itemp = classp->membersp(); itemp; itemp = itemp->nextp()) {
                const AstVar* const varp = VN_CAST(itemp, Var);
                if (!varp || !varp->isRand()) continue;
                if (varp->isRandC()) worklist.push_back(classp);
                const AstNodeDType* dtypep = varp->dtypep()->skipRefp();
                while (dtypep->isNonPackedArray()) dtypep = dtypep->subDTypep()->skipRefp();
                if (const AstClassRefDType* const refp = VN_CAST(dtypep, ClassRefDType)) {
                    reachingClasses[refp->classp()].push_back(classp);
                }
            }
        });
        while (!worklist.empty()) {
            const AstClass* const classp = worklist.back();
            worklist.pop_back();
            if (!m_randcClasses.insert(classp).second) continue;
            const auto it = reachingClasses.find(classp);
            if (it == reachingClasses.end()) continue;
            worklist.insert(worklist.end(), it->second.begin(), it->second.end());
        }
    }
    // The generator keeping the randc cycles of the randomize() with calls of the objects of a
    // class without a class generator, in the base-most class like a class generator
    AstVar* getCreateRandcHistoryp(AstClass* classp) {
        while (classp->extendsp()) classp = classp->extendsp()->classp();
        static constexpr const char* const name = "__Vrandc_history";
        if (AstVar* const varp = VN_CAST(m_memberMap.findMember(classp, name), Var)) return varp;
        AstVar* const varp = new AstVar{classp->fileline(), VVarType::MEMBER, name,
                                        classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)};
        varp->user2p(classp);
        classp->addMembersp(varp);
        m_memberMap.insert(classp, varp);
        return varp;
    }
    AstNodeStmt* implementConstraintsClearAll(FileLine* const fileline, AstVar* const genp) {
        AstCMethodHard* const clearp = new AstCMethodHard{
            fileline,
            new AstVarRef{fileline, VN_AS(genp->user2p(), NodeModule), genp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_CLEARALL};
        clearp->dtypeSetVoid();
        return clearp->makeStmt();
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
    // Get or create a size variable for a constrained dynamic array or queue.
    AstVar* createOrGetSizeVar(AstVar* const arrVarp, FileLine* const fl,
                               AstNodeDType* const signed32DTypep) {
        AstVar* sizeVarp = VN_CAST(arrVarp->user4p(), Var);
        if (!sizeVarp) {
            // Declared next to the array, so every class constraining the array's size
            // (e.g. sibling classes extending the array's class) shares it
            sizeVarp = newSizeVar(VN_AS(arrVarp->user2p(), Class),
                                  "__V" + arrVarp->name() + "_size", fl, signed32DTypep);
            arrVarp->user4p(sizeVarp);
        }
        return sizeVarp;
    }
    // Create a size variable member of classp
    AstVar* newSizeVar(AstClass* const classp, const std::string& name, FileLine* const fl,
                       AstNodeDType* const signed32DTypep) {
        AstVar* const sizeVarp = new AstVar{fl, VVarType::MEMBER, name, signed32DTypep};
        classp->addMembersp(sizeVarp);
        m_memberMap.insert(classp, sizeVarp);
        sizeVarp->user2p(classp);
        return sizeVarp;
    }
    // Get or create the size variable of an array sized through a member select
    AstVar* createOrGetMemberSizeVar(AstVar* const arrVarp, FileLine* const fl,
                                     AstNodeDType* const signed32DTypep) {
        // Separate from the array's direct size variable (createOrGetSizeVar), which is
        // registered once (AstVar::user3), in the constructor of the array's class
        AstVar*& sizeVarp = m_memberSizeVars[arrVarp];
        if (!sizeVarp) {
            sizeVarp = newSizeVar(VN_AS(arrVarp->user2p(), Class),
                                  "__V" + arrVarp->name() + "_msize", fl, signed32DTypep);
        }
        return sizeVarp;
    }
    // Size variable of arrVarp, accessed through member select mselp if not null
    AstVar* sizeVarOf(AstVar* const arrVarp, const AstMemberSel* const mselp) const {
        if (!mselp) return VN_AS(arrVarp->user4p(), Var);
        const auto it = m_memberSizeVars.find(arrVarp);
        UASSERT_OBJ(it != m_memberSizeVars.end(), arrVarp, "Member array without size variable");
        return it->second;
    }
    // Build a size >= 0 constraint expression (signed int size must be non-negative).
    // Returns a new AstConstraintExpr with user1 bits set for solver visibility.
    AstConstraintExpr* createSizeGteZeroConstraint(FileLine* const fl, AstVar* const sizeVarp,
                                                   AstNodeExpr* derefFromp = nullptr) {
        AstNodeExpr* sizeNodeExprp = nullptr;
        if (derefFromp) {
            sizeNodeExprp = buildMemberSelExprp(derefFromp, sizeVarp);
        } else {
            sizeNodeExprp = new AstVarRef{fl, sizeVarp, VAccess::READ};
        }
        sizeNodeExprp->user1(true);
        AstGteS* const sizeGtep = new AstGteS{fl, sizeNodeExprp, new AstConst{fl, 0}};
        sizeGtep->user1(true);
        return new AstConstraintExpr{fl, sizeGtep};
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
    // Returns MemberSel chain, with deepest VarRef being reference to deepestVarp
    AstNodeExpr* buildMemberSelExprp(AstNodeExpr* exprp, AstVar* deepestVarp) {
        UASSERT_OBJ(VN_IS(exprp, MemberSel) || VN_IS(exprp, VarRef), exprp,
                    "Should be MemberSel or VarRef");

        AstNodeExpr* resExprp = nullptr;
        if (const AstMemberSel* const memberSelp = VN_CAST(exprp, MemberSel)) {
            resExprp = buildMemberSelExprp(memberSelp->fromp(), nullptr);
            AstVar* varp = memberSelp->varp();
            if (deepestVarp) varp = deepestVarp;
            resExprp = new AstMemberSel{exprp->fileline(), resExprp, varp};
        } else if (const AstVarRef* const varRefp = VN_CAST(exprp, VarRef)) {
            AstVar* varp = varRefp->varp();
            if (deepestVarp) varp = deepestVarp;
            resExprp = new AstVarRef{exprp->fileline(), VN_AS(varp->user2p(), NodeModule), varp,
                                     VAccess::READWRITE};
        }

        resExprp->user1(true);
        return resExprp;
    }

    static void addUpdateRandVarsStmts(AstFunc* const updatep, AstNode* const stmtsp) {
        for (AstNode* stmtp = stmtsp; stmtp; stmtp = stmtp->nextp()) {
            if (AstBegin* const blockp = VN_CAST(stmtp, Begin)) {
                addUpdateRandVarsStmts(updatep, blockp->stmtsp());
                continue;
            }
            AstStmtExpr* const stmtExprp = VN_CAST(stmtp, StmtExpr);
            if (!stmtExprp) continue;
            AstCMethodHard* const methodp = VN_CAST(stmtExprp->exprp(), CMethodHard);
            if (!methodp || methodp->method() != VCMethod::RANDOMIZER_WRITE_VAR) continue;

            AstNodeVarRef* const varRefp = VN_AS(methodp->pinsp(), NodeVarRef);
            if (varRefp->varp()->lifetime().isStatic()) {
                // There is no need to update pointer to a static variable
                continue;
            }
            AstCMethodHard* const updateMethodp = new AstCMethodHard{
                methodp->fileline(), methodp->fromp()->cloneTreePure(false),
                VCMethod::RANDOMIZER_UPDATE_VAR, varRefp->cloneTreePure(false)};
            updateMethodp->dtypeSetVoid();
            AstNodeExpr* const namep = VN_AS(varRefp->nextp()->nextp(), NodeExpr);
            updateMethodp->addPinsp(namep->cloneTreePure(false));
            updateMethodp->method(VCMethod::RANDOMIZER_UPDATE_VAR);
            updatep->addStmtsp(updateMethodp->makeStmt());
        }
    }

    void addUpdateRandVarsBody(AstClass* const nodep, AstFunc* const randomizep) {
        UASSERT_OBJ(!nodep->hasRandVarsUpdate(), nodep, "__VupdateRandVars already exists");
        AstFunc* const updatep
            = new AstFunc{nodep->fileline(), "__VupdateRandVars", nullptr, nullptr};
        updatep->classMethod(true);
        updatep->isVirtual(true);
        updatep->keepAlive(true);
        updatep->needsSyms(false);
        nodep->addMembersp(updatep);
        nodep->hasRandVarsUpdate(true);

        for (AstClass* classp = nodep; classp;
             classp = classp->extendsp() ? classp->extendsp()->classp() : nullptr) {
            AstNodeFTask* const newp = VN_AS(m_memberMap.findMember(classp, "new"), NodeFTask);
            addUpdateRandVarsStmts(updatep, newp->stmtsp());
        }
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
                = VN_CAST(arrayElementDTypep(varp->dtypep()), ClassRefDType);
            return varp->rand().isRandomizable() && classRefp
                   && reachesByRandHandle(classRefp->classp(), targetp, visited);
        });
    }

    // Whether rand handle varp of classp, or rand array of handles, is part of a cycle of rand
    // handles
    bool inRandHandleCycle(const AstVar* varp, AstClass* classp) {
        const AstClassRefDType* const classRefp
            = VN_CAST(arrayElementDTypep(varp->dtypep()), ClassRefDType);
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
                if (isClassHandleArray(memberVarp))
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
            AstNodeExpr* const modesp = newMemberRefp(fl, objp, modeVarp);
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
            retargetMemberRef(slotsp, getRandModeVarFromClass(VN_AS(arrVarp->user2p(), Class)));
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
                                                 : getRandModeVarFromClass(classp);
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
        AstVar* const classGenp = getRandomGenerator(classp);
        if (phase != NullPhase::CHECK || !classGenp) {
            setResult(new AstConst{fl, AstConst::WidthedValue{}, 32, 1});
        } else {
            // Register the variables as new() and randomize() do, so arrays have their current
            // elements, and set the size variables the solver checks array sizes with
            VInsertionSet<AstVar*> sizedArrays;
            for (AstClass* cp = classp; cp;
                 cp = cp->extendsp() ? cp->extendsp()->classp() : nullptr) {
                copyVariableRegistrations(VN_AS(m_memberMap.findMember(cp, "new"), Func), funcp);
                for (AstVar* const arrVarp : m_sizeConstrainedArrays[cp])
                    sizedArrays.insert(arrVarp);
            }
            // Arrays with only a size constraint, and arrays of member objects, also have one
            MemberArrays memberArrays;
            addResizedArrays(classp, sizedArrays, memberArrays);
            for (AstVar* const arrVarp : sizedArrays)
                funcp->addStmtsp(newSizeVarAssign(fl, arrVarp));
            for (const auto& pathMsel : memberArrays) {
                const AstMemberSel* const mselp = pathMsel.second;
                funcp->addStmtsp(
                    newIfNonNullp(fl, newSizeVarAssign(fl, mselp->varp(), mselp), mselp));
            }
            AstNodeModule* const genModp = VN_AS(classGenp->user2p(), NodeModule);
            funcp->addStmtsp(implementConstraintsClear(fl, classGenp));
            AstTask* const setupAllTaskp = getCreateConstraintSetupFunc(classp, m_memberMap);
            funcp->addStmtsp((new AstTaskRef{fl, setupAllTaskp})->makeStmt());
            AstCExpr* const solverCallp = new AstCExpr{fl};
            solverCallp->dtypeSetBit();
            solverCallp->add(new AstVarRef{fl, genModp, classGenp, VAccess::READWRITE});
            solverCallp->add(".next_check_only(__Vm_rng)");
            setResult(solverCallp);
            classp->needRNG(true);
        }
        {
            VL_RESTORER(m_nullPhase);
            m_nullPhase = phase;
            classp->foreachMember([&](AstClass* const ownerClassp, AstVar* const memberVarp) {
                if (!memberVarp->rand().isRandomizable()) return;
                if (!VN_IS(arrayElementDTypep(memberVarp->dtypep()), ClassRefDType)) return;
                AstVarRef* const refp = new AstVarRef{fl, ownerClassp, memberVarp, VAccess::READ};
                AstNodeStmt* stmtp = newRandStmtsp(fl, refp, nullptr, fvarp);
                if (inRandHandleCycle(memberVarp, classp)) {
                    stmtp = new AstIf{
                        fl,
                        new AstLogAnd{
                            fl,
                            new AstNeq{fl,
                                       new AstVarRef{fl, ownerClassp, memberVarp, VAccess::READ},
                                       new AstConst{fl, AstConst::Null{}}},
                            new AstNot{fl, newRandomizingSelp(fl, ownerClassp, memberVarp,
                                                              VAccess::READ)}},
                        stmtp};
                }
                funcp->addStmtsp(wrapIfRandMode(
                    classp, memberVarp,
                    new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), stmtp, false}));
            });
        }
        if (phase == NullPhase::POST) addPrePostCall(classp, funcp, "post_randomize");
        if (randomizingVarp) setRandomizing(false);
    }

    // Rewrite a LogIf-of-Dist chain into nested AstConstraintIf. The outermost
    // AstLogIf shell is left for the caller's AstConstraintExpr to free; inner
    // shells are deleted here once their children are transplanted.
    AstConstraintIf* liftLogIfChainToConstraintIf(AstLogIf* logIfp) {
        FileLine* const fl = logIfp->fileline();
        AstNodeExpr* const condp = logIfp->lhsp()->unlinkFrBack();
        AstNodeExpr* const rhsp = logIfp->rhsp()->unlinkFrBack();
        AstNode* thenBodyp;
        if (AstLogIf* const innerLogIfp = VN_CAST(rhsp, LogIf)) {
            thenBodyp = liftLogIfChainToConstraintIf(innerLogIfp);
            VL_DO_DANGLING(pushDeletep(innerLogIfp), innerLogIfp);
        } else {
            thenBodyp = new AstConstraintExpr{fl, rhsp};
        }
        return new AstConstraintIf{fl, condp, thenBodyp, nullptr};
    }

    // A variable the solver draws: rand, or a std::randomize() argument
    static bool isSolvedVar(const AstVar* varp) {
        return varp->rand().isRandomizable() || varp->isStdRandomizeArg();
    }
    static bool distBoundRefsRandVar(const AstNode* boundp) {
        return boundp->exists([](const AstVarRef* vrefp) { return isSolvedVar(vrefp->varp()); });
    }

    static bool distBoundRefsModeVar(const AstNode* boundp) {
        return boundp->exists([](const AstVarRef* vrefp) {
            if (!vrefp->varp()->rand().isRandomizable()) return false;
            const RandomizeMode rmode = {.asUQuad = vrefp->varp()->user1()};
            return rmode.usesMode;
        });
    }

    // (distExpr >= lo) && (distExpr <= hi); signed comparisons for signed vars
    static AstNodeExpr* newDistRangeMembership(AstDist* distp, const AstInsideRange* irp) {
        FileLine* const fl = distp->fileline();
        const bool isSigned = distp->exprp()->isSigned();
        AstNodeExpr* const distExprGtep = distp->exprp()->cloneTreePure(false);
        AstNodeExpr* const distExprLtep = distp->exprp()->cloneTreePure(false);
        AstNodeExpr* const gep
            = isSigned ? static_cast<AstNodeExpr*>(
                             new AstGteS{fl, distExprGtep, irp->lhsp()->cloneTreePure(false)})
                       : static_cast<AstNodeExpr*>(
                             new AstGte{fl, distExprGtep, irp->lhsp()->cloneTreePure(false)});
        AstNodeExpr* const lep
            = isSigned ? static_cast<AstNodeExpr*>(
                             new AstLteS{fl, distExprLtep, irp->rhsp()->cloneTreePure(false)})
                       : static_cast<AstNodeExpr*>(
                             new AstLte{fl, distExprLtep, irp->rhsp()->cloneTreePure(false)});
        gep->user1(true);
        lep->user1(true);
        AstNodeExpr* const andp = new AstLogAnd{fl, gep, lep};
        andp->user1(true);
        return andp;
    }

    // Number of values in the range, as a 64-bit expression (0 for all 2^64 values)
    static AstNodeExpr* newDistRangeSize(FileLine* fl, const AstInsideRange* irp) {
        const bool isSigned = irp->lhsp()->isSigned();
        const AstConst* const lopCp = VN_CAST(irp->lhsp(), Const);
        const AstConst* const hipCp = VN_CAST(irp->rhsp(), Const);
        if (lopCp && hipCp && lopCp->num().mostSetBitP1() <= 64
            && hipCp->num().mostSetBitP1() <= 64) {
            // Bounds wider than 64 bits are non-negative here
            const bool sext = isSigned && lopCp->width() <= 64;
            const uint64_t lo = sext ? lopCp->num().toSQuad() : lopCp->toUQuad();
            const uint64_t hi = sext ? hipCp->num().toSQuad() : hipCp->toUQuad();
            return new AstConst{fl, AstConst::Unsized64{}, hi - lo + 1};
        }
        if (irp->lhsp()->width() > 64 || irp->rhsp()->width() > 64) {
            irp->v3warn(E_UNSUPPORTED, "Unsupported: dist range bound wider than 64 bits");
            return new AstConst{fl, AstConst::Unsized64{}, 1};
        }
        AstNodeExpr* const lo64p
            = isSigned ? static_cast<AstNodeExpr*>(
                             new AstExtendS{fl, irp->lhsp()->cloneTreePure(false), 64})
                       : static_cast<AstNodeExpr*>(
                             new AstExtend{fl, irp->lhsp()->cloneTreePure(false), 64});
        AstNodeExpr* const hi64p
            = isSigned ? static_cast<AstNodeExpr*>(
                             new AstExtendS{fl, irp->rhsp()->cloneTreePure(false), 64})
                       : static_cast<AstNodeExpr*>(
                             new AstExtend{fl, irp->rhsp()->cloneTreePure(false), 64});
        return new AstAdd{fl, new AstConst{fl, AstConst::Unsized64{}, 1ULL},
                          new AstSub{fl, hi64p, lo64p}};
    }

    struct DistBucket final {
        AstNodeExpr* rangep;  // A single value or an InsideRange
        AstNodeExpr* weightExprp;  // Effective 64-bit weight (range weight scaled by size)
        AstNodeExpr* itemWeightp;  // The item's own weight, in the AstDist
    };

    // Non-zero-weight buckets with each weight extended to 64 bits.
    std::vector<DistBucket> collectDistBuckets(AstDist* const distp) {
        FileLine* const fl = distp->fileline();
        std::vector<DistBucket> buckets;
        for (AstDistItem* const ditemp : distp->itemspList()) {
            if (const AstConst* const constp = VN_CAST(ditemp->weightp(), Const)) {
                if (constp->toUQuad() == 0) continue;
            }
            AstNodeExpr* weightExprp
                = new AstExtend{fl, ditemp->weightp()->cloneTreePure(false), 64};
            // := on a range weights every element, so scale by the range size.
            if (!ditemp->isWhole()) {
                if (const AstInsideRange* const irp = VN_CAST(ditemp->rangep(), InsideRange)) {
                    AstNodeExpr* sizep = newDistRangeSize(fl, irp);
                    if (VN_IS(sizep, Const) && VN_AS(sizep, Const)->isZero()) {
                        // All 2^64 values, saturate
                        VL_DO_DANGLING(pushDeletep(sizep), sizep);
                        sizep = new AstConst{fl, AstConst::Unsized64{},
                                             std::numeric_limits<uint64_t>::max()};
                    }
                    weightExprp = new AstMul{fl, weightExprp, sizep};
                }
            }
            buckets.push_back({ditemp->rangep(), weightExprp, ditemp->weightp()});
        }
        return buckets;
    }

    // Membership test for one bucket: a range comparison or an equality.
    static AstNodeExpr* newDistMembershipTerm(AstDist* distp, AstNodeExpr* rangep) {
        if (const AstInsideRange* const irp = VN_CAST(rangep, InsideRange)) {
            return newDistRangeMembership(distp, irp);
        }
        FileLine* const fl = distp->fileline();
        AstNodeExpr* const eqExprp = distp->exprp()->cloneTreePure(false);
        AstNodeExpr* const eqp = new AstEq{fl, eqExprp, rangep->cloneTreePure(false)};
        eqp->user1(true);
        return eqp;
    }

    // Hard constraint that the dist value is in a range with a nonzero weight.
    AstConstraintExpr* buildDistMembership(AstDist* distp,
                                           const std::vector<DistBucket>& buckets) {
        // IEEE 1800-2023 18.5.3: values outside the set never appear, and a weight of zero is
        // a constraint, also when it is only known at runtime (or solved, if it is random).
        FileLine* const fl = distp->fileline();
        AstNodeExpr* unionExprp = nullptr;
        for (const auto& bucket : buckets) {
            AstNodeExpr* memberp = newDistMembershipTerm(distp, bucket.rangep);
            if (!VN_IS(bucket.itemWeightp, Const)) {
                AstNodeExpr* const weightp = bucket.itemWeightp->cloneTreePure(false);
                AstNeq* const nzp = new AstNeq{
                    fl, weightp, new AstConst{fl, AstConst::WidthedValue{}, weightp->width(), 0}};
                nzp->user1(true);
                memberp = new AstLogAnd{fl, memberp, nzp};
                memberp->user1(true);
            }
            if (!unionExprp) {
                unionExprp = memberp;
            } else {
                unionExprp = new AstLogOr{fl, memberp, unionExprp};
                unionExprp->user1(true);
            }
        }
        return new AstConstraintExpr{fl, unionExprp};
    }

    // Gate junction with constants folded and identical terms merged.
    AstNodeExpr* newGateJoin(FileLine* fl, AstNodeExpr* ap, AstNodeExpr* bp, bool isAnd) {
        if (ap->sameTree(bp)) {
            VL_DO_DANGLING(pushDeletep(bp), bp);
            return ap;
        }
        if (VN_IS(bp, Const)) std::swap(ap, bp);
        if (VN_IS(ap, Const)) {
            const bool constWins = VN_AS(ap, Const)->isZero() == isAnd;
            if (!constWins) std::swap(ap, bp);
            VL_DO_DANGLING(pushDeletep(bp), bp);
            return ap;
        }
        if (isAnd) return new AstLogAnd{fl, ap, bp};
        return new AstLogOr{fl, ap, bp};
    }
    AstNodeExpr* newGateOr(FileLine* fl, AstNodeExpr* ap, AstNodeExpr* bp) {
        return newGateJoin(fl, ap, bp, false);
    }
    AstNodeExpr* newGateAnd(FileLine* fl, AstNodeExpr* ap, AstNodeExpr* bp) {
        return newGateJoin(fl, ap, bp, true);
    }

    // The rand_mode bit of varp: static class var, owner object's array via the
    // member select, or this object's array.
    AstNodeExpr* newModeBitRead(AstVar* varp, const AstMemberSel* mselp, AstVar* randModeVarp,
                                FileLine* fl) {
        AstNodeExpr* arrayp = nullptr;
        if (varp->lifetime().isStatic()) {
            AstClass* const ownerp = VN_CAST(varp->user2p(), Class);
            UASSERT_OBJ(ownerp, varp, "usesMode static var without an owning class");
            AstVar* const smodep = getStaticRandModeVar(ownerp);
            UASSERT_OBJ(smodep, varp, "usesMode static var without a static rand-mode array");
            arrayp = new AstVarRef{fl, VN_AS(smodep->user2p(), NodeModule), smodep, VAccess::READ};
        } else if (mselp) {
            AstVar* const memberModep = getRandModeVarFromClass(VN_AS(varp->user2p(), NodeModule));
            UASSERT_OBJ(memberModep, varp, "usesMode member without a class rand-mode array");
            arrayp = new AstMemberSel{fl, mselp->fromp()->cloneTreePure(false), memberModep};
        } else {
            UASSERT_OBJ(randModeVarp, varp, "rand_mode variable without a class mode array");
            arrayp = new AstVarRef{fl, VN_AS(randModeVarp->user2p(), NodeModule), randModeVarp,
                                   VAccess::READ};
        }
        const RandomizeMode rmode = {.asUQuad = varp->user1()};
        AstCMethodHard* const atp
            = new AstCMethodHard{fl, arrayp, VCMethod::ARRAY_AT, new AstConst{fl, rmode.index}};
        atp->dtypeSetUInt32();
        return atp;
    }

    // The rand_mode bit of one variable access, or a constant when it has none.
    // A non-rand value can never be re-drawn; a non-rand owner level is skipped.
    AstNodeExpr* newVarGate(AstVar* varp, const AstMemberSel* mselp, bool ownerLevel,
                            AstVar* randModeVarp, FileLine* fl) {
        if (!isSolvedVar(varp)) return new AstConst{fl, AstConst::BitTrue{}, ownerLevel};
        const RandomizeMode rmode = {.asUQuad = varp->user1()};
        if (!rmode.usesMode) return new AstConst{fl, AstConst::BitTrue{}};
        return newModeBitRead(varp, mselp, randModeVarp, fl);
    }

    // Change bit of one variable access, ANDed level by level down the
    // member-select owner path.
    AstNodeExpr* newAccessGate(const AstNode* nodep, bool ownerLevel, AstVar* randModeVarp,
                               FileLine* fl) {
        if (const AstMemberSel* const mselp = VN_CAST(nodep, MemberSel)) {
            return newGateAnd(fl, newVarGate(mselp->varp(), mselp, ownerLevel, randModeVarp, fl),
                              newAccessGate(mselp->fromp(), true, randModeVarp, fl));
        }
        if (const AstNodeVarRef* const refp = VN_CAST(nodep, NodeVarRef)) {
            return newVarGate(refp->varp(), nullptr, ownerLevel, randModeVarp, fl);
        }
        if (const AstNodeSel* const selp = VN_CAST(nodep, NodeSel)) {
            return newAccessGate(selp->fromp(), true, randModeVarp, fl);
        }
        if (distBoundRefsModeVar(nodep)) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: 'rand_mode' on a variable used inside this form of"
                          " 'dist' expression");
        }
        return new AstConst{fl, AstConst::BitTrue{}};
    }

    // Gate of one dist expression node: nonzero while its value can still be
    // freshly drawn. Constant when no runtime rand_mode bit is involved.
    AstNodeExpr* newDistGate(const AstNode* nodep, AstVar* randModeVarp, FileLine* fl) {
        if (VN_IS(nodep, NodeVarRef) || VN_IS(nodep, MemberSel)) {
            return newAccessGate(nodep, false, randModeVarp, fl);
        }
        // A selection is drawn through its base; the index never gates.
        if (const AstNodeSel* const selp = VN_CAST(nodep, NodeSel)) {
            return newDistGate(selp->fromp(), randModeVarp, fl);
        }
        if (const AstSel* const selp = VN_CAST(nodep, Sel)) {
            return newDistGate(selp->fromp(), randModeVarp, fl);
        }
        if (const AstStructSel* const selp = VN_CAST(nodep, StructSel)) {
            return newDistGate(selp->fromp(), randModeVarp, fl);
        }
        if (const AstCMethodHard* const methodp = VN_CAST(nodep, CMethodHard)) {
            if (methodp->method() == VCMethod::ARRAY_AT
                && VN_IS(methodp->fromp()->dtypep()->skipRefp(),  // LCOV_EXCL_BR_LINE
                         DynArrayDType)) {  // Queue form is rejected before dist lowering
                return newDistGate(methodp->fromp(), randModeVarp, fl);
            }
        }
        // A conditional re-draws through an active selector or the selected arm.
        if (const AstCond* const condp = VN_CAST(nodep, Cond)) {
            AstNodeExpr* const thenGatep = newDistGate(condp->thenp(), randModeVarp, fl);
            AstNodeExpr* const elseGatep = newDistGate(condp->elsep(), randModeVarp, fl);
            AstNodeExpr* armGatep = thenGatep;
            if (thenGatep->sameTree(elseGatep)) {
                VL_DO_DANGLING(pushDeletep(elseGatep), elseGatep);
            } else {
                armGatep
                    = new AstCond{fl, condp->condp()->cloneTreePure(false), thenGatep, elseGatep};
            }
            return newGateOr(fl, newDistGate(condp->condp(), randModeVarp, fl), armGatep);
        }
        if (const AstNodeUniop* const uopp = VN_CAST(nodep, NodeUniop)) {
            return newDistGate(uopp->lhsp(), randModeVarp, fl);
        }
        if (const AstNodeBiop* const bopp = VN_CAST(nodep, NodeBiop)) {
            return newGateOr(fl, newDistGate(bopp->lhsp(), randModeVarp, fl),
                             newDistGate(bopp->rhsp(), randModeVarp, fl));
        }
        if (distBoundRefsModeVar(nodep)) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: 'rand_mode' on a variable used inside this form of"
                          " 'dist' expression");
        }
        // Constants and remaining forms re-draw only if a rand var is inside.
        return new AstConst{fl, AstConst::BitTrue{}, distBoundRefsRandVar(nodep)};
    }

    // Weighted chain, gated on the dist value still being drawable; nullptr if it never is.
    AstNode* gateFrozenDist(AstNode* chainp, AstDist* distp, AstVar* randModeVarp) {
        // Once frozen, the hard membership alone constrains the value
        FileLine* const fl = distp->fileline();
        AstNodeExpr* gatep = newDistGate(distp->exprp(), randModeVarp, fl);
        if (VN_IS(gatep, Const)) {
            const bool drawable = !VN_AS(gatep, Const)->isZero();
            VL_DO_DANGLING(pushDeletep(gatep), gatep);
            if (drawable) return chainp;
            VL_DO_DANGLING(pushDeletep(chainp), chainp);
            return nullptr;
        }
        // A constraint 'if' condition is boolean, and the gate may be a wider mode word
        return new AstConstraintIf{fl, new AstRedOr{fl, gatep}, chainp, nullptr};
    }

    AstNodeExpr* newUniformRangePick(AstDist* distp, const AstInsideRange* irp) {
        FileLine* const fl = distp->fileline();
        AstNodeExpr* const distExprCopyp = distp->exprp()->cloneTreePure(false);
        const int distWidth = distp->exprp()->width();
        AstNodeExpr* const rangeSzp = newDistRangeSize(fl, irp);
        AstNodeExpr* offsetp = new AstRand{fl, nullptr, false};
        offsetp->dtypeSetUInt64();
        if (VN_IS(rangeSzp, Const) && VN_AS(rangeSzp, Const)->isZero()) {
            // All 2^64 values, any random value is in the range
            VL_DO_DANGLING(pushDeletep(rangeSzp), rangeSzp);
        } else {
            offsetp = new AstModDiv{fl, offsetp, rangeSzp};
        }
        offsetp = new AstCCast{fl, offsetp, distWidth};
        AstNodeExpr* const valuep = new AstAdd{fl, irp->lhsp()->cloneTreePure(false), offsetp};
        AstNodeExpr* const eqp = new AstEq{fl, distExprCopyp, valuep};
        eqp->user1(true);
        return eqp;
    }

    // Soft weighted bucket chain: select a bucket by bucketVar against cumulative weights.
    AstNode* buildWeightedBucketChain(AstDist* distp, const std::vector<DistBucket>& buckets,
                                      AstVar* bucketVarp,
                                      const std::vector<AstNodeExpr*>& cumSums) {
        FileLine* const fl = distp->fileline();
        AstNodeExpr* chainp = nullptr;
        for (int i = static_cast<int>(buckets.size()) - 1; i >= 0; --i) {
            AstNodeExpr* constraintExprp;
            const AstInsideRange* const irp = VN_CAST(buckets[i].rangep, InsideRange);
            if (irp && (distBoundRefsRandVar(irp->lhsp()) || distBoundRefsRandVar(irp->rhsp()))) {
                constraintExprp = newDistRangeMembership(distp, irp);
            } else if (irp) {
                constraintExprp = newUniformRangePick(distp, irp);
            } else {
                AstNodeExpr* const distExprCopyp = distp->exprp()->cloneTreePure(false);
                constraintExprp
                    = new AstEq{fl, distExprCopyp, buckets[i].rangep->cloneTreePure(false)};
                constraintExprp->user1(true);
            }
            if (!chainp) {
                chainp = constraintExprp;
            } else {
                AstNodeExpr* const condp
                    = new AstLte{fl, new AstVarRef{fl, bucketVarp, VAccess::READ}, cumSums[i]};
                condp->user1(true);
                chainp = new AstCond{fl, condp, constraintExprp, chainp};
                chainp->user1(true);
            }
        }
        AstConstraintExpr* const chainExprp = new AstConstraintExpr{fl, chainp};
        chainExprp->isSoft(true);
        return chainExprp;
    }

    // Replace AstDist with weighted bucket selection via AstConstraintIf chain.
    // Supports both constant and variable weight expressions.
    void lowerDistConstraints(AstNodeFTask* taskp, AstNode* constrItemsp, AstVar* randModeVarp,
                              AstConstraintForeach* foreachp = nullptr) {
        // When inside a foreach, bucket preamble stmts are stored in foreachp->user3p()
        // (as a linked list) so visit(AstConstraintForeach*) can inject them into the
        // real AstForeach body. Recursive branches share and append to the same list.
        auto addStmt = [&](AstNode* nodep) {
            if (foreachp) {
                foreachp->user3p(AstNode::addNext(foreachp->user3p(), nodep));
            } else {
                taskp->addStmtsp(nodep);
            }
        };

        for (AstNode *nextip, *itemp = constrItemsp; itemp; itemp = nextip) {
            nextip = itemp->nextp();

            // dist can appear inside an if/else or foreach constraint.
            if (AstConstraintIf* const cifp = VN_CAST(itemp, ConstraintIf)) {
                lowerDistConstraints(taskp, cifp->thensp(), randModeVarp, foreachp);
                if (cifp->elsesp()) {
                    lowerDistConstraints(taskp, cifp->elsesp(), randModeVarp, foreachp);
                }
                continue;
            }
            if (AstConstraintForeach* const cfep = VN_CAST(itemp, ConstraintForeach)) {
                lowerDistConstraints(taskp, cfep->bodyp(), randModeVarp, cfep);
                continue;
            }

            AstConstraintExpr* const constrExprp = VN_CAST(itemp, ConstraintExpr);
            if (!constrExprp) continue;

            // `cond -> x dist {...}` parses as ConstraintExpr(LogIf(cond, Dist)).
            // This pass only scans ConstraintExpr/If/Foreach for Dist, so lift the
            // LogIf chain into nested ConstraintIf first. Chains like
            // `a -> b -> dist` nest accordingly.
            if (AstLogIf* const topLogIfp = VN_CAST(constrExprp->exprp(), LogIf)) {
                AstNode* chainEndp = topLogIfp->rhsp();
                while (AstLogIf* const innerp = VN_CAST(chainEndp, LogIf)) {
                    chainEndp = innerp->rhsp();
                }
                if (VN_IS(chainEndp, Dist)) {
                    AstConstraintIf* const liftedp = liftLogIfChainToConstraintIf(topLogIfp);
                    constrExprp->replaceWith(liftedp);
                    VL_DO_DANGLING(pushDeletep(constrExprp), constrExprp);
                    lowerDistConstraints(taskp, liftedp->thensp(), randModeVarp, foreachp);
                    continue;
                }
            }

            AstDist* const distp = VN_CAST(constrExprp->exprp(), Dist);
            if (!distp) continue;

            FileLine* const fl = distp->fileline();

            std::vector<DistBucket> buckets = collectDistBuckets(distp);

            if (buckets.empty()) {
                // All weights are zero: dist is vacuously true (unconstrained)
                AstConstraintExpr* const truep
                    = new AstConstraintExpr{fl, new AstConst{fl, AstConst::BitTrue{}}};
                constrExprp->replaceWith(truep);
                VL_DO_DANGLING(pushDeletep(constrExprp), constrExprp);
                continue;
            }

            AstConstraintExpr* const membershipp = buildDistMembership(distp, buckets);

            // Build totalWeight expression: w[0] + w[1] + ... + w[N-1]
            AstNodeExpr* totalWeightExprp = nullptr;
            for (auto& bucket : buckets) {
                if (!totalWeightExprp) {
                    totalWeightExprp = bucket.weightExprp->cloneTreePure(false);
                } else {
                    totalWeightExprp = new AstAdd{fl, totalWeightExprp,
                                                  bucket.weightExprp->cloneTreePure(false)};
                    totalWeightExprp->dtypeSetUInt64();
                }
            }

            // Store totalWeight in temp var (evaluated once, used twice)
            const int distId = m_distNum++;
            const std::string totalName = "__Vdist_total" + cvtToStr(distId);
            AstVar* const totalVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, totalName, taskp->findUInt64DType()};
            totalVarp->noSubst(true);
            totalVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            totalVarp->funcLocal(true);
            totalVarp->isInternal(true);
            addStmt(totalVarp);
            addStmt(
                new AstAssign{fl, new AstVarRef{fl, totalVarp, VAccess::WRITE}, totalWeightExprp});

            // bucketVar = (rand64() % totalWeight) + 1
            const std::string bucketName = "__Vdist_bucket" + cvtToStr(distId);
            AstVar* const bucketVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, bucketName, taskp->findUInt64DType()};
            bucketVarp->noSubst(true);
            bucketVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            bucketVarp->funcLocal(true);
            bucketVarp->isInternal(true);
            addStmt(bucketVarp);

            AstNodeExpr* const randp = new AstRand{fl, nullptr, false};
            randp->dtypeSetUInt64();
            addStmt(new AstAssign{
                fl, new AstVarRef{fl, bucketVarp, VAccess::WRITE},
                new AstAdd{
                    fl, new AstConst{fl, AstConst::Unsized64{}, 1},
                    new AstModDiv{fl, randp, new AstVarRef{fl, totalVarp, VAccess::READ}}}});

            // Build cumulative sum expressions forward: cumSum[i] = w[0]+...+w[i]
            std::vector<AstNodeExpr*> cumSums;
            AstNodeExpr* runningSump = nullptr;
            for (size_t i = 0; i < buckets.size(); ++i) {
                if (!runningSump) {
                    runningSump = buckets[i].weightExprp->cloneTreePure(false);
                } else {
                    runningSump = new AstAdd{fl, runningSump,
                                             buckets[i].weightExprp->cloneTreePure(false)};
                    runningSump->dtypeSetUInt64();
                }
                cumSums.push_back(runningSump->cloneTreePure(true));
            }

            AstNode* chainp = buildWeightedBucketChain(distp, buckets, bucketVarp, cumSums);

            chainp = gateFrozenDist(chainp, distp, randModeVarp);

            // Hard membership precedes the soft bucket chain in the constraint list.
            constrExprp->replaceWith(membershipp);
            VL_DO_DANGLING(pushDeletep(constrExprp), constrExprp);
            if (chainp) membershipp->addNextHere(chainp);

            // Clean up nodes used only as clone templates (never inserted into tree)
            for (auto& bucket : buckets) {
                VL_DO_DANGLING(pushDeletep(bucket.weightExprp), bucket.weightExprp);
            }
            VL_DO_DANGLING(pushDeletep(runningSump), runningSump);
            // Last cumSum is unused (last bucket is unconditional default)
            pushDeletep(cumSums.back());
        }
    }

    // Give dist preambles operand ownership, recording the original body boundaries
    // so callers can restore the off-tree layout when needed.
    static std::vector<std::pair<AstConstraintForeach*, AstNode*>>
    attachDistPreambles(AstNode* const nodep) {
        std::vector<std::pair<AstConstraintForeach*, AstNode*>> preambles;
        nodep->foreachAndNext([&](AstConstraintForeach* const foreachp) {
            if (foreachp->user3p()) preambles.emplace_back(foreachp, foreachp->bodyp());
        });
        // A lowered dist leaves a non-empty body; remember its first statement so
        // each preamble can be detached again without walking its off-tree list.
        for (const std::pair<AstConstraintForeach*, AstNode*>& preamble : preambles) {
            AstConstraintForeach* const foreachp = preamble.first;
            AstNode* const preamblep = foreachp->user3p();
            foreachp->user3p(nullptr);
            preamblep->addNext(preamble.second->unlinkFrBackWithNext());
            foreachp->addBodyp(preamblep);
        }
        return preambles;
    }

    // Clone preamble variables and loop-index references with the bodies using them.
    static AstNode* cloneWithDistPreambles(AstNode* const nodep) {
        const std::vector<std::pair<AstConstraintForeach*, AstNode*>> preambles
            = attachDistPreambles(nodep);
        AstNode* const clonep = nodep->cloneTree(true);
        const auto restorePreamble
            = [](AstConstraintForeach* const foreachp, AstNode* const bodyp) {
                  AstNode* const preamblep = foreachp->bodyp()->unlinkFrBackWithNext();
                  foreachp->addBodyp(bodyp->unlinkFrBackWithNext());
                  foreachp->user3p(preamblep);
              };
        for (const std::pair<AstConstraintForeach*, AstNode*>& preamble : preambles) {
            restorePreamble(preamble.first->clonep(), preamble.second->clonep());
            restorePreamble(preamble.first, preamble.second);
        }
        return clonep;
    }

    static bool isDynArrOfClassTypeRecurse(const AstNodeDType* const dtypep) {
        const AstNodeDType* const refp = dtypep->skipRefp();
        if (VN_IS(refp, DynArrayDType) || VN_IS(refp, QueueDType)) {
            return isDynArrOfClassTypeRecurse(refp->subDTypep());
        } else if (VN_IS(refp, ClassRefDType)) {
            return true;
        }
        return false;
    }

    // Reference varp in the object of member select mselp, or in this object without mselp
    static AstNodeExpr* newSiblingRefp(FileLine* const fl, AstVar* const varp,
                                       const AstMemberSel* const mselp, const VAccess access) {
        if (!mselp) return new AstVarRef{fl, VN_AS(varp->user2p(), NodeModule), varp, access};
        AstMemberSel* const selp
            = new AstMemberSel{fl, mselp->fromp()->cloneTreePure(false), varp};
        selp->access(access);
        selp->foreach([access](AstVarRef* const refp) { refp->access(access); });
        return selp;
    }
    // SMT name of varp in the object of member select mselp, or in this object without mselp
    static std::string siblingSmtName(const AstVar* const varp, const AstMemberSel* const mselp) {
        return mselp ? buildMemberPath(mselp->fromp()) + "." + varp->name() : varp->name();
    }
    // Statements stmtsp on the array of member select mselp, if any, run only while the
    // handles to its object are not null
    AstNode* newIfNonNullp(FileLine* const fl, AstNode* const stmtsp,
                           const AstMemberSel* const mselp) {
        // The object of a null handle is not randomized (IEEE 1800-2023 18.4), and its
        // constraints copied into this class are not solved
        if (!mselp) return stmtsp;
        return new AstIf{fl, newHandlesActivep(m_memberMap, mselp->fromp(), false, true), stmtsp};
    }
    // Add write_var calls for each array element after resizing it with array-size constraint
    void addArrayElemRefresh(FileLine* const fl, AstVar* const arrVarp, AstFunc* const randomizep,
                             AstVar* const genp, const AstMemberSel* const mselp = nullptr) {
        AstNodeModule* const genModp = VN_AS(genp->user2p(), NodeModule);
        // Array elements of class data type are passed to the solver as separate
        // variables, so passing the original array variable is redundant, because it
        // won't be referenced
        const uint32_t unpackedDims = arrVarp->dtypep()->dimensions(false).second;
        if (isDynArrOfClassTypeRecurse(arrVarp->dtypep())) {
            if (unpackedDims > 1) {
                arrVarp->v3warn(E_UNSUPPORTED,
                                "Unsupported: Nested array element access in global constraint");
            }
            return;
        }
        AstCMethodHard* const methodp
            = new AstCMethodHard{fl, new AstVarRef{fl, genModp, genp, VAccess::READWRITE},
                                 VCMethod::RANDOMIZER_WRITE_VAR};
        methodp->dtypeSetVoid();

        methodp->addPinsp(newSiblingRefp(fl, arrVarp, mselp, VAccess::WRITE));

        const size_t width = arrayElementDTypep(arrVarp->dtypep())->width();

        methodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, width});
        AstNodeExpr* const varnamep = new AstCExpr{
            fl, AstCExpr::Pure{}, "\"" + siblingSmtName(arrVarp, mselp) + "\"", arrVarp->width()};
        varnamep->dtypep(arrVarp->dtypep());
        methodp->addPinsp(varnamep);
        methodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, unpackedDims});
        const RandomizeMode rmode = {.asUQuad = arrVarp->user1()};
        // A member object array is already registered, with its rand_mode, by the constraints
        if (rmode.usesMode && !mselp) {
            methodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, rmode.index});
        }

        randomizep->addStmtsp(newIfNonNullp(fl, methodp->makeStmt(), mselp));
    }

    AstNodeStmt* newPinSizeVariable(FileLine* const fl, AstVar* const arrVarp, AstVar* const genp,
                                    const AstMemberSel* const mselp = nullptr) {
        AstNodeModule* const genModp = VN_AS(genp->user2p(), NodeModule);
        AstVar* const sizeVarp = sizeVarOf(arrVarp, mselp);
        AstCMethodHard* const pinp
            = new AstCMethodHard{fl, new AstVarRef{fl, genModp, genp, VAccess::READWRITE},
                                 VCMethod::RANDOMIZER_PIN_VAR};
        pinp->dtypeSetVoid();
        AstCExpr* const namep
            = new AstCExpr{fl, AstCExpr::Pure{}, "\"" + siblingSmtName(sizeVarp, mselp) + "\""};
        namep->dtypeSetUInt32();
        pinp->addPinsp(namep);
        pinp->addPinsp(
            new AstConst{fl, AstConst::Unsized64{}, static_cast<uint64_t>(sizeVarp->width())});
        pinp->addPinsp(newSiblingRefp(fl, sizeVarp, mselp, VAccess::READ));
        return pinp->makeStmt();
    }

    // Assign the current size of a size-constrained array to its size variable
    AstAssign* newSizeVarAssign(FileLine* const fl, AstVar* const arrVarp,
                                const AstMemberSel* const mselp = nullptr) const {
        AstVar* const sizeVarp = sizeVarOf(arrVarp, mselp);
        AstCMethodHard* const currentSizep = new AstCMethodHard{
            fl, newSiblingRefp(fl, arrVarp, mselp, VAccess::READ), VCMethod::DYN_SIZE};
        currentSizep->dtypep(sizeVarp->dtypep());
        return new AstAssign{fl, newSiblingRefp(fl, sizeVarp, mselp, VAccess::WRITE),
                             currentSizep};
    }
    void addFrozenSizePin(FileLine* const fl, AstVar* const arrVarp, AstFunc* const randomizep,
                          AstVar* const genp, AstVar* const randModeVarp,
                          const AstMemberSel* const mselp = nullptr) {
        // The size of an array of a member object is also kept while a handle to the object
        // is inactive (IEEE 1800-2023 18.8); its constraints use the size variable even then
        const RandomizeMode rmode = {.asUQuad = arrVarp->user1()};
        AstNodeExpr* activep
            = mselp ? newHandlesActivep(m_memberMap, mselp->fromp(), true, false) : nullptr;
        if (rmode.usesMode) {
            AstNodeExpr* const modep = newModeBitRead(arrVarp, mselp, randModeVarp, fl);
            activep = activep ? new AstLogAnd{fl, activep, modep} : modep;
        }
        if (!activep) return;
        AstNode* const stmtsp = newSizeVarAssign(fl, arrVarp, mselp);
        stmtsp->addNext(new AstIf{fl, new AstLogNot{fl, activep},
                                  newPinSizeVariable(fl, arrVarp, genp, mselp)});
        randomizep->addStmtsp(newIfNonNullp(fl, stmtsp, mselp));
    }

    void collectSizeConstrainedArrays(AstClass* classp,
                                      VInsertionSet<AstVar*>& sizeArrayVars) const {
        while (classp) {
            const auto sizeArraysIt = m_sizeConstrainedArrays.find(classp);
            if (sizeArraysIt != m_sizeConstrainedArrays.end()) {
                sizeArrayVars.insert(sizeArraysIt->second.begin(), sizeArraysIt->second.end());
            }
            classp = classp->extendsp() ? classp->extendsp()->classp() : nullptr;
        }
    }

    // Add the arrays that the class constraints resize to arrVars and memberArrays
    void addResizedArrays(AstClass* const classp, VInsertionSet<AstVar*>& arrVars,
                          MemberArrays& memberArrays) {
        const AstTask* const resizeAllTaskp
            = VN_AS(m_memberMap.findMember(classp, "__Vresize_constrained_arrays"), Task);
        if (!resizeAllTaskp) return;
        // Each constraint's resize task holds only DYN_RESIZE calls on the array VarRef,
        // or on the member select of an array in a member object
        resizeAllTaskp->foreach([&](const AstTaskRef* const refp) {
            refp->taskp()->foreach([&](const AstCMethodHard* const resizep) {
                if (const AstMemberSel* const mselp = VN_CAST(resizep->fromp(), MemberSel)) {
                    memberArrays.emplace(buildMemberPath(mselp), mselp);
                } else {
                    arrVars.insert(VN_AS(resizep->fromp(), VarRef)->varp());
                }
            });
        });
    }
    // Pin the sizes of the disabled arrays among arrVars and memberArrays
    void addFrozenSizePins(const VInsertionSet<AstVar*>& arrVars, const MemberArrays& memberArrays,
                           AstFunc* const randomizep, AstVar* const genp,
                           AstVar* const randModeVarp) {
        // A disabled array keeps its current size. Pin its size proxy before solving so
        // an incompatible size constraint fails instead of resizing the frozen array.
        FileLine* const fl = randomizep->fileline();
        for (AstVar* const arrVarp : arrVars) {
            addFrozenSizePin(fl, arrVarp, randomizep, genp, randModeVarp);
        }
        for (const auto& pathMsel : memberArrays) {
            const AstMemberSel* const mselp = pathMsel.second;
            addFrozenSizePin(fl, mselp->varp(), randomizep, genp, randModeVarp, mselp);
        }
    }

    static void copyVariableRegistrations(AstFunc* const sourcep, AstFunc* const targetp) {
        for (AstNode* const stmtp : sourcep->stmtspList()) {
            // Function-call solve rounds start with the constraint clearing
            if (VN_IS(stmtp, Loop)) break;
            bool hasRegistration = false;
            bool foundClearConstraints = false;
            // stmtp is possibly begin containing a few statements
            stmtp->foreach([&](AstCMethodHard* methodp) {
                if (methodp->method() == VCMethod::RANDOMIZER_WRITE_VAR
                    || methodp->method() == VCMethod::RANDOMIZER_MARK_RANDC) {
                    hasRegistration = true;
                } else if (methodp->method() == VCMethod::RANDOMIZER_CLEARCONSTRAINTS) {
                    foundClearConstraints = true;
                }
            });
            UASSERT_OBJ(!(hasRegistration && foundClearConstraints), stmtp,
                        "Block containing both variable registration and constraint clearing");
            if (hasRegistration) targetp->addStmtsp(stmtp->cloneTree(false));
            if (foundClearConstraints) break;
        }
    }

    // Function calls with random arguments in the constraints of a class and its bases
    std::vector<ConstraintFuncCall> classFuncCalls(AstClass* const classp) {
        std::vector<ConstraintFuncCall> calls;
        classp->foreachMember([&](AstClass*, AstConstraint* const constrp) {
            const std::vector<ConstraintFuncCall>& constrCalls = m_constraintFuncCalls[constrp];
            calls.insert(calls.end(), constrCalls.begin(), constrCalls.end());
        });
        return calls;
    }
    // Function calls with random arguments in the constraints of a class's derived classes
    std::vector<ConstraintFuncCall> derivedFuncCalls(AstClass* const classp) {
        // The constraint setup is virtual, so 'randomize() with' through a base class handle
        // adds the constraints of the object's class
        std::vector<ConstraintFuncCall> calls;
        for (AstClass* const derivedp : m_derivedClasses[classp]) {
            if (derivedp->user1()) {
                // Lower its constraints first; that resets the per-class written variables
                VL_RESTORER_COPY(m_writtenVars);
                iterate(derivedp);
            }
            for (AstNode* itemp = derivedp->membersp(); itemp; itemp = itemp->nextp()) {
                if (const AstConstraint* const constrp = VN_CAST(itemp, Constraint)) {
                    const std::vector<ConstraintFuncCall>& constrCalls
                        = m_constraintFuncCalls[constrp];
                    calls.insert(calls.end(), constrCalls.begin(), constrCalls.end());
                }
            }
            const std::vector<ConstraintFuncCall> deeperCalls = derivedFuncCalls(derivedp);
            calls.insert(calls.end(), deeperCalls.begin(), deeperCalls.end());
        }
        return calls;
    }

    // Repeat the statements from firstp on in rounds that solve function arguments first
    static void addFuncRounds(AstFunc* const funcp, AstNode* const firstp, AstVar* const genp,
                              AstVar* const solveGenp, AstVar* const okVarp,
                              const AstFunc* const basicFuncp,
                              const std::vector<ConstraintFuncCall>& calls,
                              AstNode* const roundSetupp = nullptr) {
        const ConstraintFuncRounds rounds{calls};
        if (!rounds.lastRound()) {
            if (roundSetupp) VL_DO_DANGLING(roundSetupp->deleteTree(), roundSetupp);
            return;
        }
        FileLine* const fl = funcp->fileline();
        AstNodeModule* const genModp = VN_CAST(genp->user2p(), NodeModule);
        AstLoop* const loopp = new AstLoop{fl, roundSetupp};
        for (AstNode *stmtp = firstp, *nextp; stmtp; stmtp = nextp) {
            nextp = stmtp->nextp();
            // Declarations stay outside of the loop
            if (!VN_IS(stmtp, Var)) loopp->addStmtsp(stmtp->unlinkFrBack());
        }
        // Basic randomization, which also randomizes member objects and calls their
        // pre/post_randomize, happens once, in the final round
        std::vector<std::pair<AstNode*, AstFuncRef*>> basicCalls;  // Statement and call
        for (AstNode* stmtp = loopp->stmtsp(); stmtp; stmtp = stmtp->nextp()) {
            stmtp->foreach([&](AstFuncRef* refp) {
                if (refp->taskp() == basicFuncp) basicCalls.emplace_back(stmtp, refp);
            });
        }
        AstVar* const basicOkVarp = basicCalls.empty()
                                        ? nullptr
                                        : new AstVar{fl, VVarType::BLOCKTEMP, "__Vbasic_round_ok",
                                                     funcp->findBasicDType(VBasicDTypeKwd::BIT)};
        if (basicOkVarp) {
            basicOkVarp->funcLocal(true);
            funcp->addStmtsp(basicOkVarp);
            funcp->addStmtsp(new AstAssign{fl, new AstVarRef{fl, basicOkVarp, VAccess::WRITE},
                                           new AstConst{fl, AstConst::BitTrue{}}});
        }
        for (const auto& stmtCall : basicCalls) {
            AstFuncRef* const refp = stmtCall.second;
            refp->replaceWith(new AstVarRef{fl, basicOkVarp, VAccess::READ});
            AstCMethodHard* const finalp
                = new AstCMethodHard{fl, new AstVarRef{fl, genModp, genp, VAccess::READ},
                                     VCMethod::RANDOMIZER_FUNC_ROUND_FINAL};
            finalp->dtypeSetBit();
            stmtCall.first->addHereThisAsNext(new AstIf{
                fl, finalp,
                new AstAssign{fl, new AstVarRef{fl, basicOkVarp, VAccess::WRITE}, refp}});
        }
        // Stop at a failing round: the later rounds have its constraints too
        AstCMethodHard* const nextRoundp = new AstCMethodHard{
            fl, new AstVarRef{fl, genModp, genp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_FUNC_ROUND_NEXT,
            new AstVarRef{fl, VN_CAST(solveGenp->user2p(), NodeModule), solveGenp, VAccess::READ}};
        nextRoundp->dtypeSetBit();
        loopp->addStmtsp(new AstLoopTest{
            fl, loopp, new AstLogAnd{fl, new AstVarRef{fl, okVarp, VAccess::READ}, nextRoundp}});
        AstCMethodHard* const startp
            = new AstCMethodHard{fl, new AstVarRef{fl, genModp, genp, VAccess::READWRITE},
                                 VCMethod::RANDOMIZER_FUNC_ROUND_START,
                                 new AstConst{fl, static_cast<uint32_t>(rounds.lastRound())}};
        startp->addPinsp(new AstCExpr{fl, AstCExpr::Pure{}, rounds.roundList()});
        startp->dtypeSetVoid();
        funcp->addStmtsp(startp->makeStmt());
        funcp->addStmtsp(loopp);
        AstCMethodHard* const endp
            = new AstCMethodHard{fl, new AstVarRef{fl, genModp, genp, VAccess::READWRITE},
                                 VCMethod::RANDOMIZER_FUNC_ROUND_END};
        endp->dtypeSetVoid();
        funcp->addStmtsp(endp->makeStmt());
    }

    // sizeSolve for the solve of array sizes before the final solve
    static AstCExpr* newSolverCallp(AstVar* const genp, const bool sizeSolve = false) {
        AstCExpr* const callp = new AstCExpr{genp->fileline()};
        callp->dtypeSetBit();
        callp->add(new AstVarRef{genp->fileline(), VN_CAST(genp->user2p(), NodeModule), genp,
                                 VAccess::READWRITE});
        callp->add(sizeSolve ? ".next_size(__Vm_rng)" : ".next(__Vm_rng)");
        return callp;
    }
    // Solve for the element values if the size solve succeeded
    static AstIf* newFinalSolvep(FileLine* fl, AstVar* sizeOkVarp, AstVar* finalOkVarp,
                                 AstVar* genp) {
        // A failed size solve already reported why, and the call fails anyway
        return new AstIf{fl, new AstVarRef{fl, sizeOkVarp, VAccess::READ},
                         new AstAssign{fl, new AstVarRef{fl, finalOkVarp, VAccess::WRITE},
                                       newSolverCallp(genp)}};
    }

    AstVar* addSizeSolvep(AstFunc* const randomizep, AstVar* const genp) {
        FileLine* const fl = randomizep->fileline();
        AstVar* const sizeOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vsize_ok",
                                              randomizep->findBasicDType(VBasicDTypeKwd::BIT)};
        sizeOkVarp->funcLocal(true);
        randomizep->addStmtsp(sizeOkVarp);
        randomizep->addStmtsp(new AstAssign{fl, new AstVarRef{fl, sizeOkVarp, VAccess::WRITE},
                                            newSolverCallp(genp, true)});
        return sizeOkVarp;
    }

    // Rebuild constraints after resize
    void addConstraintRebuild(AstFunc* const randomizep, AstVar* const setupGenp,
                              AstVar* const solveGenp, const VInsertionSet<AstVar*>& sizeArrayVars,
                              const VInsertionSet<AstVar*>& resizedArrayVars,
                              const MemberArrays& memberArrays,
                              const std::set<std::string>& writtenVars,
                              AstNode* const setupStmtsp) {
        FileLine* const fl = randomizep->fileline();
        for (AstVar* const arrVarp : sizeArrayVars) {
            addArrayElemRefresh(fl, arrVarp, randomizep, setupGenp);
        }
        // Member object arrays are registered when constraints use their elements
        for (const auto& pathMsel : memberArrays) {
            if (!writtenVars.count(pathMsel.first)) continue;
            const AstMemberSel* const mselp = pathMsel.second;
            addArrayElemRefresh(fl, mselp->varp(), randomizep, setupGenp, mselp);
        }
        randomizep->addStmtsp(implementConstraintsClear(fl, setupGenp));
        randomizep->addStmtsp(setupStmtsp);
        // The arrays are resized once, so their sizes must not change in the final solve
        for (AstVar* const arrVarp : resizedArrayVars) {
            randomizep->addStmtsp(newPinSizeVariable(fl, arrVarp, solveGenp));
        }
        for (const auto& pathMsel : memberArrays) {
            const AstMemberSel* const mselp = pathMsel.second;
            randomizep->addStmtsp(
                newIfNonNullp(fl, newPinSizeVariable(fl, mselp->varp(), solveGenp, mselp), mselp));
        }
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
        VL_RESTORER(m_distNum);
        m_modp = nodep;
        m_randCaseNum = 0;
        m_distNum = 0;
        m_writtenVars.clear();  // Each class has its own set of written variables

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
        AstVar* const randModeVarp = getRandModeVarFromClass(nodep);
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
        AstNodeExpr* beginValp = nullptr;
        bool sizePhase = false;  // Sizes are solved and arrays resized before the final solve
        AstNode* roundsFirstp = nullptr;  // First statement of the solve
        AstVar* genp = getRandomGenerator(nodep);
        if (genp) {
            // Phase 1: Process all constraints (create tasks, run ConstraintExprVisitor)
            // Setup task refs are NOT added to setupAllTaskp here -- done in phase 2
            AstTask* const prepareArraysTaskp = createPrepareConstrainedArraysTask(nodep);
            nodep->foreachMember([&](AstClass* const classp, AstConstraint* const constrp) {
                AstTask* taskp = VN_AS(constrp->user2p(), Task);
                if (!taskp) {
                    taskp = newSetupConstraintTask(classp, constrp->name());
                    constrp->user2p(taskp);
                }

                if (AstTask* const resizeTaskp = VN_CAST(constrp->user3p(), Task)) {
                    AstTask* const resizeAllTaskp = getCreateAggrResizeTask(nodep);
                    AstTaskRef* const resizeTaskRefp
                        = new AstTaskRef{constrp->fileline(), resizeTaskp};
                    resizeTaskRefp->classOrPackagep(classp);
                    resizeAllTaskp->addStmtsp(
                        wrapIfConstraintMode(nodep, constrp, resizeTaskRefp->makeStmt()));
                }

                if (constrp->itemsp()) expandUniqueElementList(constrp->itemsp());
                if (constrp->itemsp()) {
                    lowerDistConstraints(taskp, constrp->itemsp(), randModeVarp);
                }
                VInsertionSet<AstVar*>& sizeArrays = m_sizeConstrainedArrays[classp];
                const ConstraintExprVisitor exprVisitor{
                    classp,       m_memberMap,        constrp->itemsp(),     nullptr,       genp,
                    randModeVarp, m_writtenVars,      &m_uniqueConstraintId, m_uniqueNames, taskp,
                    &sizeArrays,  prepareArraysTaskp, &m_newWrittenVars};
                if (constrp->itemsp()) skipInactiveElems(constrp);
                std::vector<ConstraintFuncCall>& calls = m_constraintFuncCalls[constrp];
                const std::vector<ConstraintFuncCall>& newCalls = exprVisitor.funcCalls();
                calls.insert(calls.end(), newCalls.begin(), newCalls.end());
                if (constrp->itemsp()) {
                    AstNode* stmtsp = wrapIfConstraintMode(
                        nodep, constrp, constrp->itemsp()->unlinkFrBackWithNext());
                    // The constraints of objects of inactive handles are not solved
                    const auto it = m_cloneObjps.find(constrp);
                    if (it != m_cloneObjps.end()) {
                        if (AstNodeExpr* const activep
                            = newHandlesActivep(m_memberMap, it->second.objp, true, true)) {
                            stmtsp = new AstIf{constrp->fileline(), activep, stmtsp};
                        }
                    }
                    taskp->addStmtsp(stmtsp);
                }
            });

            // Phase 2: Add setup task refs in depth order (deepest first = lowest priority)
            // Ensures outer-scope soft constraints override inner-scope (IEEE 18.5.13)
            {
                // Count nesting depth by GLOBAL_CONSTRAINT_SEPARATOR occurrences
                const auto constraintDepth = [](const AstConstraint* constrp) {
                    int depth = 0;
                    size_t pos = 0;
                    while ((pos = constrp->name().find(GLOBAL_CONSTRAINT_SEPARATOR, pos))
                           != std::string::npos) {
                        ++depth;
                        pos += std::strlen(GLOBAL_CONSTRAINT_SEPARATOR);
                    }
                    return depth;
                };
                int maxDepth = 0;
                nodep->foreachMember([&](AstClass* const, AstConstraint* const constrp) {
                    maxDepth = std::max(maxDepth, constraintDepth(constrp));
                });
                AstTask* const setupAllTaskp = getCreateConstraintSetupFunc(nodep, m_memberMap);
                for (int d = maxDepth; d >= 0; --d) {
                    nodep->foreachMember(
                        [&](AstClass* const classp, AstConstraint* const constrp) {
                            if (constraintDepth(constrp) != d) return;
                            AstTask* const taskp = VN_AS(constrp->user2p(), Task);
                            AstTaskRef* const setupTaskRefp
                                = new AstTaskRef{constrp->fileline(), taskp};
                            setupTaskRefp->classOrPackagep(classp);
                            setupAllTaskp->addStmtsp(setupTaskRefp->makeStmt());
                        });
                }
                if (AstNode* const pinsp = newClassElemModePinsp(nodep, genp)) {
                    setupAllTaskp->addStmtsp(pinsp);
                }
            }
            // For derived classes: save every array that has is size-constrained array to
            // generate array element refresh later
            VInsertionSet<AstVar*> sizeArrayVars;
            std::set<std::string>& writtenVars = m_classWrittenVars[nodep];
            writtenVars = m_writtenVars;
            if (nodep->extendsp()) {
                AstClass* parentClassp = nodep->extendsp()->classp();
                collectSizeConstrainedArrays(parentClassp, sizeArrayVars);
                while (parentClassp) {
                    // Inherited constraints were lowered, and their variables registered, there
                    const auto writtenIt = m_classWrittenVars.find(parentClassp);
                    if (writtenIt != m_classWrittenVars.end()) {
                        writtenVars.insert(writtenIt->second.begin(), writtenIt->second.end());
                    }
                    parentClassp
                        = parentClassp->extendsp() ? parentClassp->extendsp()->classp() : nullptr;
                }
            }
            roundsFirstp = implementConstraintsClear(fl, genp);
            randomizep->addStmtsp(roundsFirstp);

            const auto sizeArraysIt = m_sizeConstrainedArrays.find(nodep);
            if (sizeArraysIt != m_sizeConstrainedArrays.end()) {
                for (AstVar* const arrVarp : sizeArraysIt->second) sizeArrayVars.insert(arrVarp);
            }
            AstTask* const setupAllTaskp = getCreateConstraintSetupFunc(nodep, m_memberMap);
            if (!sizeArrayVars.empty() && prepareArraysTaskp->stmtsp()) {
                // Before the setup registers the elements
                randomizep->addStmtsp((new AstTaskRef{fl, prepareArraysTaskp})->makeStmt());
            }
            AstTaskRef* const setupTaskRefp = new AstTaskRef{fl, setupAllTaskp};
            randomizep->addStmtsp(setupTaskRefp->makeStmt());

            VInsertionSet<AstVar*> pinnedArrays = sizeArrayVars;
            MemberArrays memberArrays;
            addResizedArrays(nodep, pinnedArrays, memberArrays);
            addFrozenSizePins(pinnedArrays, memberArrays, randomizep, genp, randModeVarp);

            // A member object array is randomized with the outer object, after its resize
            sizePhase = !sizeArrayVars.empty() || !memberArrays.empty();
            if (sizePhase) {
                AstVar* const sizeOkVarp = addSizeSolvep(randomizep, genp);
                if (AstTask* const resizeAllTaskp
                    = VN_AS(m_memberMap.findMember(nodep, "__Vresize_constrained_arrays"), Task)) {
                    randomizep->addStmtsp(
                        new AstIf{fl, new AstVarRef{fl, sizeOkVarp, VAccess::READ},
                                  (new AstTaskRef{fl, resizeAllTaskp})->makeStmt(), nullptr});
                }
                // Basic randomization fills the resized arrays. It runs before the final
                // solve, so it cannot override a solved leaf of a member object.
                AstFunc* const basicRandomizep
                    = V3Randomize::newRandomizeFunc(m_memberMap, nodep, BASIC_RANDOMIZE_FUNC_NAME);
                randomizep->addStmtsp(new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE},
                                                    new AstFuncRef{fl, basicRandomizep}});
                addConstraintRebuild(randomizep, genp, genp, sizeArrayVars, pinnedArrays,
                                     memberArrays, writtenVars,
                                     (new AstTaskRef{fl, setupAllTaskp})->makeStmt());

                AstVar* const finalOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vfinal_ok",
                                                       nodep->findBasicDType(VBasicDTypeKwd::BIT)};
                finalOkVarp->funcLocal(true);
                randomizep->addStmtsp(finalOkVarp);
                randomizep->addStmtsp(newFinalSolvep(fl, sizeOkVarp, finalOkVarp, genp));

                beginValp = new AstAnd{fl, new AstVarRef{fl, fvarp, VAccess::READ},
                                       new AstAnd{fl, new AstVarRef{fl, sizeOkVarp, VAccess::READ},
                                                  new AstVarRef{fl, finalOkVarp, VAccess::READ}}};
            } else {
                beginValp = newSolverCallp(genp);
            }
            if (randModeVarp) {
                AstNodeModule* const randModeClassp = VN_AS(randModeVarp->user2p(), Class);
                AstNodeFTask* const newp
                    = VN_AS(m_memberMap.findMember(randModeClassp, "new"), NodeFTask);
                UASSERT_OBJ(newp, randModeClassp, "No new() in class");
                addSetRandMode(newp, genp, randModeVarp);
            }
            if (AstVar* const staticRandModeVarp = getStaticRandModeVar(nodep)) {
                // Wire the shared static rand_mode queue into the class generator.
                AstNodeFTask* const newp = VN_AS(m_memberMap.findMember(nodep, "new"), NodeFTask);
                UASSERT_OBJ(newp, nodep, "No new() in class");
                addSetStaticRandMode(newp, genp, staticRandModeVarp);
            }
        } else {
            beginValp = new AstConst{fl, AstConst::WidthedValue{}, 32, 1};
        }

        addUpdateRandVarsBody(nodep, randomizep);

        AstFunc* const basicRandomizep
            = V3Randomize::newRandomizeFunc(m_memberMap, nodep, BASIC_RANDOMIZE_FUNC_NAME);
        addBasicRandomizeBody(basicRandomizep, nodep, randModeVarp);
        AstVarRef* const fvarRefp = new AstVarRef{fl, fvarp, VAccess::WRITE};
        if (sizePhase) {
            randomizep->addStmtsp(new AstAssign{fl, fvarRefp, beginValp});
        } else {
            // A basicFirst owner basic-randomizes first, then the solver overrides the
            // constrained leaves, so a globally-constrained leaf (not user3) is still
            // basic-randomized when its type is randomized standalone.
            randomizep->addStmtsp(new AstAssign{
                fl, fvarRefp, basicFirst ? new AstFuncRef{fl, basicRandomizep} : beginValp});

            // Size-only resize fallback (no element constraint, so no two-pass phase).
            // Must run after the solver .next() that sets the size variable; emit it
            // after whichever assignment below holds the solver call.
            const auto emitResizeFallback = [&]() {
                if (AstTask* const resizeAllTaskp
                    = VN_AS(m_memberMap.findMember(nodep, "__Vresize_constrained_arrays"), Task)) {
                    AstTaskRef* const resizeTaskRefp = new AstTaskRef{fl, resizeAllTaskp};
                    randomizep->addStmtsp(resizeTaskRefp->makeStmt());
                }
            };
            if (!basicFirst) emitResizeFallback();

            AstVarRef* const fvarRefReadp = fvarRefp->cloneTree(false);
            fvarRefReadp->access(VAccess::READ);

            AstNodeExpr* const secondHalfp
                = basicFirst ? beginValp : new AstFuncRef{fl, basicRandomizep};
            randomizep->addStmtsp(new AstAssign{fl, fvarRefp->cloneTree(false),
                                                new AstAnd{fl, fvarRefReadp, secondHalfp}});

            if (basicFirst) emitResizeFallback();
        }
        if (roundsFirstp) {
            addFuncRounds(randomizep, roundsFirstp, genp, genp, fvarp, basicRandomizep,
                          classFuncCalls(nodep));
        }

        // Call nested post_randomize on rand class-type members (IEEE 18.4.1)
        if (classHasRandClassMembers(nodep)) {
            AstTask* const postTaskp = getCreateNestedCallbackTask(nodep, "post");
            populateNestedCallbackTask(postTaskp, nodep, "post_randomize");
            randomizep->addStmtsp((new AstTaskRef{fl, postTaskp})->makeStmt());
        }

        addPrePostCall(nodep, randomizep, "post_randomize");
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
                UASSERT_OBJ(m_elemModeArrays.count(arrVarp), nodep,
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
                                             : getRandModeVarFromClass(randModeTarget.classp);
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
                // Clear old constraints and variables for std::randomize with clause
                AstNode* const roundsFirstp
                    = implementConstraintsClearAll(randomizeFuncp->fileline(), stdrandp);
                randomizeFuncp->addStmtsp(roundsFirstp);
                AstBegin* const setupBlockp = new AstBegin{
                    fl, "__Vsetup_constraints", withp->exprp()->unlinkFrBackWithNext(), true};
                lowerDistConstraints(randomizeFuncp, setupBlockp->stmtsp(), nullptr);
                AstNode* const capturedTreep = setupBlockp->stmtsp();
                randomizeFuncp->addStmtsp(setupBlockp);
                expandUniqueElementList(capturedTreep);
                AstNode* const itemsp
                    = setupBlockp->stmtsp();  // Expansion may delete the first item
                const ConstraintExprVisitor exprVisitor{
                    nullptr,       m_memberMap, itemsp,        setupBlockp,
                    stdrandp,      nullptr,     m_writtenVars, &m_uniqueConstraintId,
                    m_uniqueNames, nullptr};
                AstCExpr* const solverCallp = new AstCExpr{fl};
                solverCallp->dtypeSetBit();
                solverCallp->add(new AstVarRef{fl, stdrandp, VAccess::READWRITE});
                solverCallp->add(".next()");
                AstVar* const fvarp = VN_AS(randomizeFuncp->fvarp(), Var);
                AstNodeExpr* const andExprp
                    = new AstAnd{fl, new AstVarRef{fl, fvarp, VAccess::READ}, solverCallp};
                randomizeFuncp->addStmtsp(
                    new AstAssign{fl, new AstVarRef{fl, fvarp, VAccess::WRITE}, andExprp});
                addFuncRounds(randomizeFuncp, roundsFirstp, stdrandp, stdrandp, fvarp, nullptr,
                              exprVisitor.funcCalls());
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
        std::vector<ConstraintFuncCall> calls = derivedFuncCalls(classp);

        AstVar* const classGenp = getRandomGenerator(classp);
        AstVar* const localGenp
            = new AstVar{nodep->fileline(), VVarType::BLOCKTEMP, "randomizer",
                         classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)};
        localGenp->funcLocal(true);

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

        // Last statement before the solve, which starts with registering the arrays' elements
        AstNode* const solveAfterp
            = randomizeFuncp->stmtsp() ? randomizeFuncp->stmtsp()->lastp() : nullptr;
        // Add constraints clearing code
        if (classGenp) {
            randomizeFuncp->addStmtsp(
                implementConstraintsClear(randomizeFuncp->fileline(), classGenp));
        }

        randomizeFuncp->addStmtsp(localGenp);

        AstFunc* const basicRandomizeFuncp
            = V3Randomize::newRandomizeFunc(m_memberMap, classp, BASIC_RANDOMIZE_FUNC_NAME);
        AstFuncRef* const basicRandomizeFuncCallp
            = new AstFuncRef{nodep->fileline(), basicRandomizeFuncp};

        // Copy (derive) class constraints if present
        if (classGenp) {
            AstTask* const constrSetupFuncp = getCreateConstraintSetupFunc(classp, m_memberMap);
            AstTaskRef* const callp = new AstTaskRef{nodep->fileline(), constrSetupFuncp};
            randomizeFuncp->addStmtsp(callp->makeStmt());
            randomizeFuncp->addStmtsp(new AstAssign{
                nodep->fileline(), new AstVarRef{nodep->fileline(), localGenp, VAccess::WRITE},
                new AstVarRef{nodep->fileline(), VN_AS(classGenp->user2p(), NodeModule), classGenp,
                              VAccess::READ}});
        }

        // The randc cycles continue across calls (IEEE 1800-2023 18.4.2), but this call's
        // generator also holds its own constraints, so only its randc cycles are kept
        AstVar* const randcHistoryp = !m_randcClasses.count(classp) ? nullptr
                                      : classGenp                   ? classGenp
                                                  : getCreateRandcHistoryp(classp);
        if (randcHistoryp && !classGenp) {
            randomizeFuncp->addStmtsp(
                newRandcHistoryFromp(nodep->fileline(), localGenp, randcHistoryp));
        }

        // Set rand mode if present (not needed if classGenp exists and was copied)
        AstVar* const randModeVarp = getRandModeVarFromClass(classp);
        if (!classGenp && randModeVarp) addSetRandMode(randomizeFuncp, localGenp, randModeVarp);
        if (!classGenp) {
            if (AstVar* const sVarp = getStaticRandModeVar(classp)) {
                addSetStaticRandMode(randomizeFuncp, localGenp, sVarp);
            }
        }

        // Generate constraint setup code and a hardcoded call to the solver
        AstBegin* const setupBlockp = new AstBegin{nodep->fileline(), "__Vsetup_constraints",
                                                   withp->exprp()->unlinkFrBackWithNext(), true};
        // Dist bucket draws go into the function, ahead of the constraints reading them
        lowerDistConstraints(randomizeFuncp, setupBlockp->stmtsp(), randModeVarp);
        AstNode* const capturedTreep = setupBlockp->stmtsp();
        randomizeFuncp->addStmtsp(setupBlockp);
        // With a class generator the class setup above added them
        if (!classGenp) {
            if (AstNode* const pinsp = newClassElemModePinsp(classp, localGenp)) {
                randomizeFuncp->addStmtsp(pinsp);
            }
        }

        // Pre-scan captured tree for .size on dynamic arrays and queues and replace
        // with size variables, using shared createOrGetSizeVar helper.
        // After CaptureVisitor, fromp() of .size is AstMemberSel (not VarRef),
        // so extract the underlying variable from the MemberSel chain.
        // Collect the class-wide resize call and the with-block's own resize
        // statements to run after a successful solver call.
        AstNode* resizeStmtsp = nullptr;
        if (AstTask* const resizeAllTaskp
            = VN_AS(m_memberMap.findMember(classp, "__Vresize_constrained_arrays"), Task)) {
            resizeStmtsp = (new AstTaskRef{nodep->fileline(), resizeAllTaskp})->makeStmt();
        }
        VInsertionSet<AstVar*> inlineSizedArrays;  // Arrays of classp this with-block resizes
        MemberArrays memberArrays;  // Arrays of member objects this call resizes
        {
            std::vector<AstCMethodHard*> sizeMethodps;
            capturedTreep->foreachAndNext([&](AstCMethodHard* methodp) {
                // Not of an associative array, whose size is not random (IEEE 1800-2023 18.4)
                if (methodp->method() == VCMethod::DYN_SIZE) sizeMethodps.push_back(methodp);
            });
            for (AstCMethodHard* const methodp : sizeMethodps) {
                // Extract array variable from fromp (VarRef or MemberSel after capture)
                AstVar* arrVarp = nullptr;
                AstNodeExpr* const rootExprp = methodp->fromp();
                if (AstMemberSel* memberSelp = VN_CAST(rootExprp, MemberSel)) {
                    arrVarp = memberSelp->varp();
                    // A non-random array is not randomized however it is reached (IEEE
                    // 1800-2023 18.4), so its size is a state value
                    if (!arrVarp->rand().isRandomizable()) continue;
                    while (VN_IS(memberSelp->fromp(), MemberSel)) {
                        memberSelp = VN_CAST(memberSelp->fromp(), MemberSel);
                    }
                    // Only variables that are part of object that randomize is called on shall be
                    // randomized (18.6.1), skip randomization if deepest variable is reference to
                    // __Vthis
                    const AstNodeExpr* const fromp = memberSelp->fromp();
                    if (const AstVarRef* const varRefp = VN_CAST(fromp, VarRef)) {
                        if (varRefp->varp() == captured.getThisp()) continue;
                    } else {
                        fromp->v3warn(E_UNSUPPORTED, "Unsupported: Unsupported size constraint "
                                                     "inside 'with' statement of type "
                                                         << fromp->dtypep()->prettyTypeName());
                        continue;
                    }
                } else if (AstVarRef* const varRefp = VN_CAST(rootExprp, VarRef)) {
                    arrVarp = varRefp->varp();
                }
                if (!arrVarp) continue;
                // Only handle rand-declared dynamic array and queue variables
                if (!arrVarp->rand().isRandomizable()) continue;
                FileLine* const fl = methodp->fileline();
                // An array of a rand member object has the size variable of the class
                // constraints reaching it, and is resized by each with-block sizing it.
                // The size of an array of another object is a state value.
                const bool viaMember = VN_IS(rootExprp, MemberSel);
                if (viaMember && !rootExprp->user1()) continue;
                const std::string memberPath = viaMember ? buildMemberPath(rootExprp) : "";
                AstVar* const sizeVarp
                    = viaMember ? createOrGetMemberSizeVar(arrVarp, fl, methodp->findIntDType())
                                : createOrGetSizeVar(arrVarp, fl, methodp->findIntDType());
                // arrVarp and sizeVarp may live in a base class when the
                // array is inherited; route VarRefs through their declaring
                // class so V3Scope can resolve them.
                // Each with-block sizing the array resizes it, even if another created sizeVarp
                if (viaMember ? !memberArrays.count(memberPath)
                              : inlineSizedArrays.insert(arrVarp)) {
                    AstNodeExpr* const resizeVarRefp = buildMemberSelExprp(rootExprp, arrVarp);
                    if (viaMember)
                        memberArrays.emplace(memberPath, VN_AS(resizeVarRefp, MemberSel));
                    AstNodeExpr* const sizeExprp = buildMemberSelExprp(rootExprp, sizeVarp);
                    // Append size >= 0 constraint so ConstraintExprVisitor processes it
                    capturedTreep->addNext(createSizeGteZeroConstraint(fl, sizeVarp, rootExprp));
                    AstCMethodHard* const resizep
                        = new AstCMethodHard{fl, resizeVarRefp, VCMethod::DYN_RESIZE, sizeExprp};
                    resizep->dtypep(methodp->findVoidDType());
                    resizeStmtsp = AstNode::addNext(resizeStmtsp, new AstStmtExpr{fl, resizep});
                }
                AstNodeExpr* const sizeNodeExprp = buildMemberSelExprp(rootExprp, sizeVarp);
                methodp->replaceWith(sizeNodeExprp);
                VL_DO_DANGLING(methodp->deleteTree(), methodp);
            }
        }

        // Keep an independent copy of the lowered with-block constraints to rebuild
        // them against post-resize arrays if a size phase is needed below.
        AstNode* const capturedClonep = cloneWithDistPreambles(capturedTreep);

        // Arrays that gain a size var from THIS with-block's own inline .size()==expr
        // constraint (as opposed to a class-level one) and are also referenced by a
        // unique{} constraint here; see the m_sizeConstrainedArraysp comment in
        // ConstraintExprVisitor::visit(AstConstraintUnique). Merged below with any
        // class-level size-constrained arrays.
        VInsertionSet<AstVar*> allSizeArrays;
        expandUniqueElementList(capturedTreep);
        AstNode* const itemsp = setupBlockp->stmtsp();  // Expansion may delete the first item
        const ConstraintExprVisitor exprVisitor{
            classp,        m_memberMap,  itemsp,        setupBlockp,
            localGenp,     randModeVarp, m_writtenVars, &m_uniqueConstraintId,
            m_uniqueNames, nullptr,      &allSizeArrays};

        // A with-block touching a size-constrained array (class-level, or made so by
        // its own inline .size()==expr above) needs the same two-phase solve as the
        // plain randomize() path above: solve once to pin down sizes, resize, then
        // rebuild and solve again so unique{}/element constraints see the arrays'
        // final (post-resize) length rather than their pre-solve (usually empty) one.
        FileLine* const fl = nodep->fileline();
        collectSizeConstrainedArrays(classp, allSizeArrays);
        // Arrays resized by the class constraints also need their sizes solved first and
        // pinned; their elements are not re-registered unless constrained as above
        VInsertionSet<AstVar*> pinnedArrays = allSizeArrays;
        addResizedArrays(classp, pinnedArrays, memberArrays);
        // Arrays of member objects are resized only in the size phase
        const bool needsSizePhase = !pinnedArrays.empty() || !memberArrays.empty();
        AstVar* const retVarp = VN_AS(randomizeFuncp->fvarp(), Var);
        // Arrays whose size this call solves; each is pinned when frozen and for the final solve
        VInsertionSet<AstVar*> sizedArrays = pinnedArrays;
        sizedArrays.insert(inlineSizedArrays.begin(), inlineSizedArrays.end());
        addFrozenSizePins(sizedArrays, memberArrays, randomizeFuncp, localGenp, randModeVarp);

        if (needsSizePhase) {
            AstVar* const finalOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vfinal_ok",
                                                   classp->findBasicDType(VBasicDTypeKwd::BIT)};
            finalOkVarp->funcLocal(true);
            randomizeFuncp->addStmtsp(finalOkVarp);

            // First pass: solve to determine sizes
            AstVar* const sizeOkVarp = addSizeSolvep(randomizeFuncp, localGenp);

            // Resize constrained arrays before rebuilding constraints: both any
            // class-wide resize task (class-level size constraints) and this
            // with-block's own inline-size resize statements.
            if (resizeStmtsp) {
                AstIf* const ifp
                    = new AstIf{fl, new AstVarRef{fl, sizeOkVarp, VAccess::READ}, resizeStmtsp};
                randomizeFuncp->addStmtsp(ifp);
            }

            // Call __VBasicRand as its own statement after the resize, so it also fills
            // new elements, and before the final solve, so the solver's answer sticks.
            // The single-statement form below (basicRandomizeFuncCallp combined inline
            // with the solver call) relies on statement hoisting for that order, which
            // would place it after the final solve here.
            AstVar* const basicOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vbasic_ok",
                                                   classp->findBasicDType(VBasicDTypeKwd::BIT)};
            basicOkVarp->funcLocal(true);
            randomizeFuncp->addStmtsp(basicOkVarp);
            randomizeFuncp->addStmtsp(new AstAssign{
                fl, new AstVarRef{fl, basicOkVarp, VAccess::WRITE}, basicRandomizeFuncCallp});

            // Clear this call's constraints, then rebuild them fresh against the
            // resized arrays: the class's own constraints (re-copied from a freshly
            // re-run class setup, if any), and this with-block's own constraints
            // (re-lowered from the pristine clone snapshotted above).
            {
                AstCMethodHard* const clearp
                    = new AstCMethodHard{fl, new AstVarRef{fl, localGenp, VAccess::READWRITE},
                                         VCMethod::RANDOMIZER_CLEARCONSTRAINTS};
                clearp->dtypeSetVoid();
                randomizeFuncp->addStmtsp(clearp->makeStmt());
            }
            if (classGenp) {
                randomizeFuncp->addStmtsp(implementConstraintsClear(fl, classGenp));
                AstTask* const constrSetupFuncp2
                    = getCreateConstraintSetupFunc(classp, m_memberMap);
                randomizeFuncp->addStmtsp((new AstTaskRef{fl, constrSetupFuncp2})->makeStmt());
                // The copy keeps the randc cycles of this call, as its size solve left them
                AstVar* const randcKeepp
                    = randcHistoryp
                          ? new AstVar{fl, VVarType::BLOCKTEMP, "__Vrandc_keep",
                                       classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)}
                          : nullptr;
                if (randcKeepp) {
                    randcKeepp->funcLocal(true);
                    randomizeFuncp->addStmtsp(randcKeepp);
                    randomizeFuncp->addStmtsp(newRandcHistoryFromp(fl, randcKeepp, localGenp));
                }
                randomizeFuncp->addStmtsp(
                    new AstAssign{fl, new AstVarRef{fl, localGenp, VAccess::WRITE},
                                  new AstVarRef{fl, VN_AS(classGenp->user2p(), NodeModule),
                                                classGenp, VAccess::READ}});
                if (randcKeepp) {
                    randomizeFuncp->addStmtsp(newRandcHistoryFromp(fl, localGenp, randcKeepp));
                }
            } else if (AstNode* const pinsp = newClassElemModePinsp(classp, localGenp)) {
                randomizeFuncp->addStmtsp(pinsp);
            }

            // Refresh array element tables after resize, on localGenp -- AFTER the
            // classGenp copy above, so this overwrites whatever (possibly now-stale,
            // pre-resize) entry that copy brought in. write_var's compile-time,
            // once-ever registration (AstVar::user3()) does not re-run on the second
            // lowering pass below, so it is redone here by hand, same as the
            // class-level pattern above.
            // The with-block re-registers the member object arrays it uses below; those
            // the class constraints use are registered again here
            const std::set<std::string>& classWrittenVars = m_classWrittenVars[classp];
            for (const auto& pathMsel : memberArrays) {
                if (!classWrittenVars.count(pathMsel.first)) continue;
                const AstMemberSel* const mselp = pathMsel.second;
                addArrayElemRefresh(fl, mselp->varp(), randomizeFuncp, localGenp, mselp);
            }
            for (AstVar* const arrVarp : pinnedArrays) {
                // The size var itself needs write_var'ing here too, unconditionally:
                // the pin below always references it by name, but nothing else in
                // THIS with-block's own (re-)lowered tree is guaranteed to touch it --
                // unlike the class-level pattern, where the class's constraint setup
                // always re-asserts the arr.size() == expr equality (and so always
                // write_vars the size var as a side effect), a with-block that adds
                // unique{} to an array sized by a *different* call/constraint has no
                // size-var reference of its own to trigger that.
                if (AstVar* const sizeVarp = VN_CAST(arrVarp->user4p(), Var)) {
                    AstCMethodHard* const sizeMethodp
                        = new AstCMethodHard{fl, new AstVarRef{fl, localGenp, VAccess::READWRITE},
                                             VCMethod::RANDOMIZER_WRITE_VAR};
                    sizeMethodp->dtypeSetVoid();
                    AstNodeModule* const sizeClassp = VN_AS(sizeVarp->user2p(), NodeModule);
                    AstVarRef* const sizeVarRefp
                        = new AstVarRef{fl, sizeClassp, sizeVarp, VAccess::WRITE};
                    sizeVarRefp->classOrPackagep(sizeClassp);
                    sizeMethodp->addPinsp(sizeVarRefp);
                    sizeMethodp->addPinsp(new AstConst{fl, AstConst::Unsized64{},
                                                       static_cast<uint64_t>(sizeVarp->width())});
                    AstNodeExpr* const sizeNamep = new AstCExpr{
                        fl, AstCExpr::Pure{}, "\"" + sizeVarp->name() + "\"", sizeVarp->width()};
                    sizeMethodp->addPinsp(sizeNamep);
                    sizeMethodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 0});
                    randomizeFuncp->addStmtsp(sizeMethodp->makeStmt());
                }
                if (!allSizeArrays.exists(arrVarp)) continue;  // Elements left to __VBasicRand

                if (isDynArrOfClassTypeRecurse(arrVarp->dtypep())) {
                    const uint32_t unpackedDims = arrVarp->dtypep()->dimensions(false).second;
                    if (unpackedDims > 1) {
                        // A genuinely nested (unpackedDims > 1) dynamic array of
                        // class-typed elements already hits unrelated, pre-existing
                        // unsupported-constraint/internal-error paths well before
                        // reaching a randomize() with {} two-phase solve, so this
                        // can't currently be exercised from here.
                        arrVarp->v3warn(  // LCOV_EXCL_LINE
                            E_UNSUPPORTED,
                            "Unsupported: Nested array element access in global constraint");
                    }
                    continue;
                }
                AstCMethodHard* const methodp
                    = new AstCMethodHard{fl, new AstVarRef{fl, localGenp, VAccess::READWRITE},
                                         VCMethod::RANDOMIZER_WRITE_VAR};
                methodp->dtypeSetVoid();

                AstNodeModule* const arrClassp = VN_AS(arrVarp->user2p(), NodeModule);
                AstVarRef* const varRefp = new AstVarRef{fl, arrClassp, arrVarp, VAccess::WRITE};
                varRefp->classOrPackagep(arrClassp);
                methodp->addPinsp(varRefp);

                uint32_t dimension = 0;
                if (VN_IS(arrVarp->dtypep(), UnpackArrayDType)
                    || VN_IS(arrVarp->dtypep(), DynArrayDType)
                    || VN_IS(arrVarp->dtypep(), QueueDType)) {
                    const std::pair<uint32_t, uint32_t> dims
                        = arrVarp->dtypep()->dimensions(/*includeBasic=*/true);
                    dimension = dims.second;
                }

                const size_t width = arrayElementDTypep(arrVarp->dtypep())->width();
                methodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, width});
                AstNodeExpr* const varnamep = new AstCExpr{
                    fl, AstCExpr::Pure{}, "\"" + arrVarp->name() + "\"", arrVarp->width()};
                varnamep->dtypep(arrVarp->dtypep());
                methodp->addPinsp(varnamep);
                methodp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, dimension});

                randomizeFuncp->addStmtsp(methodp->makeStmt());
            }

            AstBegin* const elementSetupBlockp
                = new AstBegin{fl, "__Vsetup_constraints", capturedClonep, true};
            randomizeFuncp->addStmtsp(elementSetupBlockp);
            expandUniqueElementList(capturedClonep);
            // Expansion may delete the first item
            AstNode* const elementItemsp = elementSetupBlockp->stmtsp();
            ConstraintExprVisitor{
                classp,       m_memberMap,   elementItemsp,         elementSetupBlockp, localGenp,
                randModeVarp, m_writtenVars, &m_uniqueConstraintId, m_uniqueNames,      nullptr};

            // Pin the sizes so the final solve can't move them
            for (AstVar* const arrVarp : sizedArrays) {
                randomizeFuncp->addStmtsp(newPinSizeVariable(fl, arrVarp, localGenp));
            }

            for (const auto& pathMsel : memberArrays) {
                const AstMemberSel* const mselp = pathMsel.second;
                randomizeFuncp->addStmtsp(newIfNonNullp(
                    fl, newPinSizeVariable(fl, mselp->varp(), localGenp, mselp), mselp));
            }

            // Final solve: element values with sizes pinned
            randomizeFuncp->addStmtsp(newFinalSolvep(fl, sizeOkVarp, finalOkVarp, localGenp));

            randomizeFuncp->addStmtsp(new AstAssign{
                fl, new AstVarRef{fl, retVarp, VAccess::WRITE},
                new AstAnd{fl,
                           new AstAnd{fl, new AstVarRef{fl, basicOkVarp, VAccess::READ},
                                      new AstVarRef{fl, sizeOkVarp, VAccess::READ}},
                           new AstVarRef{fl, finalOkVarp, VAccess::READ}}});
        } else {
            // Preambles held in user3p are off-tree; reattach them so deletion frees them.
            attachDistPreambles(capturedClonep);
            VL_DO_DANGLING(capturedClonep->deleteTree(), capturedClonep);

            // Call the solver and set return value
            AstCExpr* const solverCallp = newSolverCallp(localGenp);
            randomizeFuncp->addStmtsp(
                new AstAssign{fl, new AstVarRef{fl, retVarp, VAccess::WRITE},
                              new AstAnd{fl, basicRandomizeFuncCallp, solverCallp}});

            // Resize constrained arrays only when solver succeeds
            if (resizeStmtsp) {
                AstIf* const ifp
                    = new AstIf{fl, new AstVarRef{fl, retVarp, VAccess::READ}, resizeStmtsp};
                randomizeFuncp->addStmtsp(ifp);
            }
        }
        {
            // The class's constraints were set up in the class's generator, which holds the
            // rounds and is copied into this call's generator
            const std::vector<ConstraintFuncCall> classCalls = classFuncCalls(classp);
            calls.insert(calls.end(), classCalls.begin(), classCalls.end());
            const std::vector<ConstraintFuncCall>& newCalls = exprVisitor.funcCalls();
            calls.insert(calls.end(), newCalls.begin(), newCalls.end());
            addFuncRounds(
                randomizeFuncp, solveAfterp ? solveAfterp->nextp() : randomizeFuncp->stmtsp(),
                classGenp ? classGenp : localGenp, localGenp, retVarp, basicRandomizeFuncp, calls,
                classGenp ? nullptr : implementConstraintsClear(fl, localGenp));
        }
        // A failed call leaves the randc cycles alone
        if (randcHistoryp) {
            randomizeFuncp->addStmtsp(
                new AstIf{fl, new AstVarRef{fl, retVarp, VAccess::READ},
                          newRandcHistoryFromp(fl, randcHistoryp, localGenp)});
        }

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
        VL_RESTORER_CLEAR(m_constraintSizedArrays);
        m_constraintp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstCMethodHard* nodep) override {
        iterateChildren(nodep);
        FileLine* const fl = nodep->fileline();
        // The size of an associative array is not random (IEEE 1800-2023 18.4), so it stays
        // a state value
        if (m_constraintp && nodep->fromp()->user1() && nodep->method() == VCMethod::DYN_SIZE) {
            AstClass* const classp = VN_AS(m_modp, Class);
            // The array is a member of this class, or of a rand member object (global
            // constraints, IEEE 1800-2023 18.5.8) reached through a member select chain
            AstNodeExpr* const arrayp = nodep->fromp();
            AstMemberSel* const memberSelp = VN_CAST(arrayp, MemberSel);
            AstNodeExpr* rootp = arrayp;
            while (AstMemberSel* const selp = VN_CAST(rootp, MemberSel)) rootp = selp->fromp();
            // Warning from ConstraintExprVisitor will be thrown
            if (!VN_IS(rootp, VarRef)) return;
            AstVar* const queueVarp = getVarFromRef(arrayp);
            AstVar* const sizeVarp
                = memberSelp ? createOrGetMemberSizeVar(queueVarp, fl, nodep->findIntDType())
                             : createOrGetSizeVar(queueVarp, fl, nodep->findIntDType());
            const auto newSizeRefp = [&]() -> AstNodeExpr* {
                if (memberSelp) return buildMemberSelExprp(memberSelp, sizeVarp);
                return new AstVarRef{fl, VN_AS(sizeVarp->user2p(), NodeModule), sizeVarp,
                                     VAccess::READ};
            };
            // Each constraint sizing the array resizes it and guards its size, so
            // constraint_mode(0) leaves the array unchanged only when all are off
            if (m_constraintSizedArrays.insert(buildMemberPath(arrayp)).second) {
                AstTask* resizerTaskp = VN_AS(m_constraintp->user3p(), Task);
                if (!resizerTaskp) {
                    resizerTaskp = newResizeConstrainedArrayTask(classp, m_constraintp->name());
                    m_constraintp->user3p(resizerTaskp);
                }
                AstCMethodHard* const resizep = new AstCMethodHard{
                    fl, arrayp->unlinkFrBack(), VCMethod::DYN_RESIZE, newSizeRefp()};
                resizep->dtypep(nodep->findVoidDType());
                resizerTaskp->addStmtsp(
                    newIfNonNullp(fl, new AstStmtExpr{fl, resizep}, memberSelp));

                // Since size variable is signed int, we need additional constraint
                // to make sure it is always >= 0.
                m_constraintp->addItemsp(createSizeGteZeroConstraint(fl, sizeVarp, memberSelp));
            }
            AstNodeExpr* const sizeRefp = newSizeRefp();
            sizeRefp->user1(true);
            nodep->replaceWith(sizeRefp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
        }
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
        , m_cloneObjps{cloneObjps}
        , m_elemModeArrays{elemModeArrays} {
        nodep->foreach([&](AstClass* const classp) {
            if (classp->extendsp())
                m_derivedClasses[classp->extendsp()->classp()].push_back(classp);
        });
        findRandcClasses(nodep);
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
    // Enums inside packed arrays and packed structs constrain their bit slice
    const auto addSlice = [&](const AstNodeDType* sliceDtp, int lsb) {
        const std::string term
            = enumDomainTerm(sliceDtp, "((_ extract " + cvtToStr(lsb + sliceDtp->width() - 1) + " "
                                           + cvtToStr(lsb) + ") " + valueExpr + ")");
        if (!term.empty()) terms.push_back(term);
        return !term.empty();
    };
    if (const AstPackArrayDType* const arrayDtp = VN_CAST(dtypep, PackArrayDType)) {
        const AstNodeDType* const elemDtp = arrayDtp->subDTypep();
        for (int i = 0; i < arrayDtp->elementsConst(); ++i) {
            if (!addSlice(elemDtp, i * elemDtp->width())) break;  // No element holds an enum
        }
    } else if (const AstStructDType* const structDtp = VN_CAST(dtypep, StructDType)) {
        if (structDtp->packed()) {
            for (const AstMemberDType* const memberp : structDtp->memberspList()) {
                addSlice(memberp->subDTypep(), memberp->lsb());
            }
        }
    }
    return terms.empty() ? "" : smtJoin("and", terms);
}

std::string V3Randomize::enumDomain(AstNodeDType* dtypep) {
    return enumDomainTerm(arrayElementDTypep(dtypep), "__Ve");
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
        const bool isProcess = basep->name() == "process";
        AstCStmt* const stmtp = new AstCStmt{basep->fileline(), isProcess ? "m_process->srandom("
                                                                          : "__Vm_rng.srandom("};
        stmtp->add(new AstVarRef{basep->fileline(), ivarp, VAccess::READ});
        stmtp->add(");");
        funcp->addStmtsp(stmtp);
        if (!isProcess) basep->needRNG(true);
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
