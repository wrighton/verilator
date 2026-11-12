// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: SMT-LIB constraint solver back-end
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
// V3SolverSmt's Transformations:
//
// Implements V3SolverBackend for solvers driven through SMT-LIB2 text by the
// VlRandomizer runtime (include/verilated_random.h), e.g. z3 or cvc5.
//
// Each class with constraints:
//      * gets a VlRandomizer member ('constraint'), set up in new()
//      * each constraint block becomes a <name>_setup_constraint task, which
//        registers variables (write_var) and adds SMT-LIB expressions (hard,
//        soft) built by ConstraintExprVisitor; __Vsetup_constraints calls them
//        in priority order (deepest-nested global constraints first)
//      * randomize() clears, re-runs the setup and calls the solver; arrays
//        with constrained sizes take a two-phase solve (sizes, then elements)
// Each randomize() with {...} and std::randomize() with {...}:
//      * lowers its constraints into a local VlRandomizer, derived from the
//        class one for randomize() with {...}
//
// Runs within the V3Randomize pass, and uses the AstNode user fields it
// documents; those owned by this back-end are:
//  AstVar::user3()         -> bool. Handled in constraints (shared with front end)
//  AstClass::user3p()      -> AstVar*.  Constrained randomizer variable
//  AstConstraint::user2p() -> AstTask*. Pointer to constraint setup procedure
//  AstConstraint::user3p() -> AstTask*. Pointer to resize procedure
//  AstConstraintForeach::user3p() -> AstNodeStmt*. Dist bucket preamble stmts (foreach case)
//  AstVar::user4p()        -> AstVar*.  Size variable for constrained queues
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "verilatedos.h"

#include "V3SolverSmt.h"

#include "V3Const.h"
#include "V3File.h"
#include "V3MemberMap.h"
#include "V3Randomize.h"
#include "V3Stats.h"
#include "V3Task.h"
#include "V3UniqueNames.h"

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################
// Helpers shared by the lowering visitors

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

// Whether the handles on the path objp have rand_mode on (if modes) and are not null (if
// nonNull), nullptr if nothing to check
static AstNodeExpr* newHandlesActivep(VMemberMap& memberMap, AstNodeExpr* objp, bool modes,
                                      bool nonNull) {
    // The object of an inactive (IEEE 1800-2023 18.8) or null (18.4) handle is not
    // randomized. objp is a chain of member and element selects from a member of 'this'.
    AstNodeExpr* condp = nullptr;
    while (objp) {
        AstNodeExpr* elemArrayp = nullptr;  // Array of the element objp selects
        if (AstNodeSel* const nodeSelp = VN_CAST(objp, NodeSel)) {
            elemArrayp = nodeSelp->fromp();
        } else if (AstCMethodHard* const atp = VN_CAST(objp, CMethodHard)) {
            elemArrayp = atp->fromp();
        }
        if (elemArrayp) {
            // An element handle is checked like a member handle, after its owners
            if (nonNull && VN_IS(objp->dtypep()->skipRefp(), ClassRefDType)) {
                FileLine* const fl = objp->fileline();
                AstNodeExpr* const levelp
                    = new AstNeq{fl, objp->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
                condp = condp ? new AstLogAnd{fl, levelp, condp} : levelp;
            }
            objp = elemArrayp;
            continue;
        }
        AstMemberRef* const selp = VN_CAST(objp, MemberRef);
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
                           : RandModeVars::randModeVarp(VN_AS(varp->user2p(), NodeModule));
            AstNodeExpr* modesp;
            if (ownerp && !isStatic) {
                modesp = new AstMemberRef{fl, ownerp->cloneTree(false), modeVarp};
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

// SMT name of a variable reference or of a member select chain rooted at one
static std::string buildMemberPath(const AstNodeExpr* const exprp) {
    if (const AstVarRef* const refp = VN_CAST(exprp, VarRef)) return refp->name();
    const AstMemberRef* const memberSelp = VN_CAST(exprp, MemberRef);
    UASSERT_OBJ(memberSelp, exprp, "Unexpected node type in MemberRef chain");
    return buildMemberPath(memberSelp->fromp()) + "." + memberSelp->name();
}

// Whether dtypep is an array of arrays whose elements are class handles
static bool isMultiDimHandleArray(AstNodeDType* dtypep) {
    dtypep = dtypep->skipRefp();
    return dtypep->isNonPackedArray() && dtypep->subDTypep()->skipRefp()->isNonPackedArray()
           && VN_IS(RandomizeUtil::arrayElementDTypep(dtypep), ClassRefDType);
}

class SmtUtil final {
public:
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

    // Create __Vsetup_constraints function if non existant inside memberMap,
    // if existant return one already present
    static AstTask* getCreateConstraintSetupFunc(AstClass* classp, VMemberMap& memberMap) {
        static const char* const name = "__Vsetup_constraints";
        AstTask* setupAllTaskp = VN_AS(memberMap.findMember(classp, name), Task);
        if (setupAllTaskp) return setupAllTaskp;
        setupAllTaskp = new AstTask{classp->fileline(), "__Vsetup_constraints"};
        setupAllTaskp->classMethod(true);
        setupAllTaskp->isVirtual(true);
        classp->addMembersp(setupAllTaskp);
        memberMap.insert(classp, setupAllTaskp);
        return setupAllTaskp;
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
    // Constraint items are lowered in place, so while lowered they are held in the declarations
    // of a temporary block. When lowered to statements, the block stands where these go.
    static AstBegin* newItemsHolderp(FileLine* fl, AstNode* itemsp) {
        AstBegin* const holderp = new AstBegin{fl, "[EditWrapper]", nullptr, false};
        holderp->addDeclsp(itemsp);
        return holderp;
    }
    // Replace 'holderp' with the statements the items it holds were lowered to
    static void replaceWithLowered(AstBegin* holderp) {
        if (AstNode* const stmtsp = holderp->declsp()) {
            holderp->addNextHere(VN_AS(stmtsp->unlinkFrBackWithNext(), NodeStmt));
        }
        VL_DO_DANGLING(holderp->unlinkFrBack()->deleteTree(), holderp);
    }
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
        const auto pair = m_rounds.emplace(name, int{VISITING});
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
// Structured fast-domain lowering, before dist is rewritten to a procedural
// bucket draw plus SMT membership/soft choices. Unsupported original items
// explicitly disable the optimization for the whole invocation.

class FastConstraintBuilder final {
    struct Range final {
        uint64_t lo;
        uint64_t hi;
        uint64_t weight = 1;
        uint64_t divisor = 1;
    };
    using Ranges = std::vector<Range>;
    AstVar* const m_genp;
    AstNodeExpr* m_targetp = nullptr;  // Original bound variable access
    AstVar* m_varp = nullptr;
    bool m_supported = true;
    std::vector<AstNodeExpr*> m_constants;  // Detached, constified bound copies

    static Ranges unite(Ranges ranges) {
        std::sort(ranges.begin(), ranges.end(),
                  [](const Range& a, const Range& b) { return a.lo < b.lo; });
        Ranges result;
        for (const Range& range : ranges) {
            if (!result.empty() && range.lo <= result.back().hi + 1) {
                result.back().hi = std::max(result.back().hi, range.hi);
            } else {
                result.push_back(range);
            }
        }
        return result;
    }
    static Ranges intersect(const Ranges& a, const Ranges& b) {
        Ranges result;
        size_t i = 0;
        size_t j = 0;
        while (i < a.size() && j < b.size()) {
            const uint64_t lo = std::max(a[i].lo, b[j].lo);
            const uint64_t hi = std::min(a[i].hi, b[j].hi);
            if (lo <= hi) result.push_back({lo, hi});
            if (a[i].hi < b[j].hi)
                ++i;
            else
                ++j;
        }
        return result;
    }
    uint64_t mask() const { return (uint64_t{1} << m_varp->width()) - 1; }
    uint64_t key(uint64_t bits) const {
        return (bits & mask()) ^ (m_varp->isSigned() ? uint64_t{1} << (m_varp->width() - 1) : 0);
    }
    void findTarget(AstNodeExpr* exprp) {
        exprp->foreach([&](AstNodeExpr* const nodep) {
            AstVar* varp = nullptr;
            if (AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
                if (refp->user1()) varp = refp->varp();
            } else if (AstMemberRef* const refp = VN_CAST(nodep, MemberRef)) {
                // Only a capture of this object's scalar, not a path through a
                // possibly null/aliased member object.
                if (VN_IS(refp->fromp(), VarRef) && refp->fromp()->user1()
                    && refp->user2p() == refp->varp()->user2p())
                    varp = refp->varp();
            }
            if (!varp || !(varp->rand().isRandomizable() || varp->isStdRandomizeArg())) return;
            const AstNodeDType* const dtp = varp->dtypep()->skipRefToEnump();
            if ((!VN_IS(dtp, BasicDType) && !VN_IS(dtp, EnumDType)) || !dtp->isIntegralOrPacked()
                || varp->width() > 32 || varp->width() < 1 || varp->rand().isRandC()) {
                m_supported = false;
                return;
            }
            if (m_targetp && !m_targetp->sameTree(nodep)) m_supported = false;
            m_targetp = nodep;
            m_varp = varp;
        });
        if (!m_targetp) m_supported = false;
    }
    bool isTarget(const AstNodeExpr* exprp) const {
        if (const AstExtend* const extendp = VN_CAST(exprp, Extend)) {
            if (m_varp->isSigned()) return false;
            exprp = extendp->lhsp();
        } else if (const AstExtendS* const extendp = VN_CAST(exprp, ExtendS)) {
            if (!m_varp->isSigned()) return false;
            exprp = extendp->lhsp();
        }
        return m_targetp->sameTree(exprp);
    }
    AstConst* constant(AstNodeExpr* exprp) {
        AstConst* constp = VN_CAST(exprp, Const);
        if (!constp && exprp->isPure() && !exprp->exists([](const AstNodeVarRef*) { return true; })
            && !exprp->exists([](const AstMemberRef*) { return true; })
            && !exprp->exists([](const AstNodeFTaskRef*) { return true; })) {
            AstNodeExpr* const foldedp = V3Const::constifyEdit(exprp->cloneTreePure(false));
            m_constants.push_back(foldedp);
            constp = VN_CAST(foldedp, Const);
        }
        if (!constp || constp->width() > 64 || constp->num().isOpaque()
            || constp->num().isFourState())
            m_supported = false;
        return m_supported ? constp : nullptr;
    }
    Ranges comparison(AstNodeBiop* nodep) {
        AstNodeExpr* boundp = nodep->rhsp();
        AstNodeExpr* targetp = nodep->lhsp();
        bool reversed = false;
        if (!isTarget(targetp)) {
            std::swap(targetp, boundp);
            reversed = true;
        }
        if (!isTarget(targetp) || targetp->width() > 64) {
            m_supported = false;
            return {};
        }
        const AstConst* const constp = constant(boundp);
        if (!constp) return {};
        if (VN_IS(nodep, Eq) || VN_IS(nodep, EqWild) || VN_IS(nodep, Neq)) {
            const uint64_t bits = constp->toUQuad();
            uint64_t extended = bits & mask();
            if (m_varp->isSigned() && (extended & (uint64_t{1} << (m_varp->width() - 1)))) {
                extended |= ~mask();
            }
            const uint64_t operandMask = targetp->width() == 64
                                             ? std::numeric_limits<uint64_t>::max()
                                             : (uint64_t{1} << targetp->width()) - 1;
            Ranges equal;
            if ((extended & operandMask) == bits) equal.push_back({key(bits), key(bits)});
            if (!VN_IS(nodep, Neq)) return equal;
            if (equal.empty()) return {{0, mask()}};
            Ranges result;
            if (equal[0].lo) result.push_back({0, equal[0].lo - 1});
            if (equal[0].hi < mask()) result.push_back({equal[0].hi + 1, mask()});
            return result;
        }
        const bool signedCompare
            = VN_IS(nodep, LtS) || VN_IS(nodep, LteS) || VN_IS(nodep, GtS) || VN_IS(nodep, GteS);
        if (signedCompare != m_varp->isSigned()) {
            m_supported = false;
            return {};
        }
        if (!signedCompare
            && constp->toUQuad() > static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) {
            const bool lowerBound = (VN_IS(nodep, Gt) || VN_IS(nodep, Gte)) != reversed;
            return lowerBound ? Ranges{} : Ranges{{0, mask()}};
        }
        const int64_t bound
            = signedCompare ? constp->num().toSQuad() : static_cast<int64_t>(constp->toUQuad());
        const int64_t min = signedCompare ? -(int64_t{1} << (m_varp->width() - 1)) : 0;
        const int64_t max = signedCompare ? (int64_t{1} << (m_varp->width() - 1)) - 1
                                          : static_cast<int64_t>(mask());
        bool lower
            = VN_IS(nodep, Gt) || VN_IS(nodep, Gte) || VN_IS(nodep, GtS) || VN_IS(nodep, GteS);
        const bool inclusive
            = VN_IS(nodep, Gte) || VN_IS(nodep, Lte) || VN_IS(nodep, GteS) || VN_IS(nodep, LteS);
        if (reversed) lower = !lower;
        // Clamp before incrementing/decrementing, including the extreme 64-bit bound.
        if (lower) {
            if (bound > max || (bound == max && !inclusive)) return {};
            const int64_t lo = bound < min ? min : bound + !inclusive;
            return {{key(static_cast<uint64_t>(lo)), key(static_cast<uint64_t>(max))}};
        }
        if (bound < min || (bound == min && !inclusive)) return {};
        const int64_t hi = bound > max ? max : bound - !inclusive;
        return {{key(static_cast<uint64_t>(min)), key(static_cast<uint64_t>(hi))}};
    }
    void parseUnion(AstNodeExpr* nodep, Ranges& ranges) {
        if (AstLogOr* const orp = VN_CAST(nodep, LogOr)) {
            parseUnion(orp->lhsp(), ranges);
            parseUnion(orp->rhsp(), ranges);
        } else {
            const Ranges term = parse(nodep);
            ranges.insert(ranges.end(), term.begin(), term.end());
        }
    }
    Ranges parse(AstNodeExpr* nodep) {
        if (const AstConst* const constp = VN_CAST(nodep, Const)) {
            if (constp->num().isFourState()) m_supported = false;
            return constp->isZero() ? Ranges{} : Ranges{{0, mask()}};
        }
        if (AstLogAnd* const andp = VN_CAST(nodep, LogAnd)) {
            const Ranges a = parse(andp->lhsp());
            const Ranges b = parse(andp->rhsp());
            return intersect(a, b);
        }
        if (VN_IS(nodep, LogOr)) {
            Ranges ranges;
            parseUnion(nodep, ranges);
            return unite(std::move(ranges));
        }
        if (VN_IS(nodep, Eq) || VN_IS(nodep, EqWild) || VN_IS(nodep, Neq) || VN_IS(nodep, Lt)
            || VN_IS(nodep, Lte) || VN_IS(nodep, Gt) || VN_IS(nodep, Gte) || VN_IS(nodep, LtS)
            || VN_IS(nodep, LteS) || VN_IS(nodep, GtS) || VN_IS(nodep, GteS))
            return comparison(VN_AS(nodep, NodeBiop));
        m_supported = false;
        return {};
    }
    Ranges distribution(AstDist* distp) {
        if (!isTarget(distp->exprp())) m_supported = false;
        Ranges ranges;
        for (AstDistItem* const itemp : distp->itemspList()) {
            const AstConst* const weightp = constant(itemp->weightp());
            if (!weightp) return {};
            if (weightp->isSigned() && weightp->num().isNegative()) {
                m_supported = false;
                return {};
            }
            const AstInsideRange* const rangep = VN_CAST(itemp->rangep(), InsideRange);
            const AstConst* const lop = constant(rangep ? rangep->lhsp() : itemp->rangep());
            const AstConst* const hip = constant(rangep ? rangep->rhsp() : itemp->rangep());
            if (!lop || !hip) return {};
            // Bounds are already context-sized by V3Width. Reject rather than
            // truncate wider bounds, which could admit values outside the SV set.
            if (lop->width() != m_varp->width() || hip->width() != m_varp->width()) {
                m_supported = false;
                return {};
            }
            const uint64_t lo = key(lop->toUQuad());
            const uint64_t hi = key(hip->toUQuad());
            if (lo > hi || !weightp->toUQuad()) continue;
            ranges.push_back({lo, hi, weightp->toUQuad(), itemp->isWhole() ? hi - lo + 1 : 1});
        }
        if (ranges.empty()) m_supported = false;  // Preserve the existing all-zero dist policy
        return ranges;
    }
    AstCMethodHard* newCallp(FileLine* fl, VCMethod method) const {
        AstCMethodHard* const callp = new AstCMethodHard{
            fl, new AstVarRef{fl, VN_AS(m_genp->user2p(), NodeModule), m_genp, VAccess::READWRITE},
            method};
        callp->dtypeSetVoid();
        return callp;
    }
    AstNodeStmt* newDomainp(FileLine* fl, const Ranges& ranges, bool soft, bool dist,
                            bool isEnum = false) const {
        AstCMethodHard* const beginp = newCallp(fl, VCMethod::RANDOMIZER_FAST_BEGIN);
        AstNodeExpr* const targetp = m_targetp->cloneTreePure(false);
        if (AstVarRef* const refp = VN_CAST(targetp, VarRef)) refp->access(VAccess::READWRITE);
        if (AstMemberRef* const refp = VN_CAST(targetp, MemberRef))
            refp->access(VAccess::READWRITE);
        beginp->addPinsp(targetp);
        beginp->addPinsp(new AstConst{fl, static_cast<uint32_t>(m_varp->width())});
        beginp->addPinsp(new AstConst{fl, AstConst::BitTrue{}, m_varp->isSigned()});
        beginp->addPinsp(new AstConst{fl, AstConst::BitTrue{}, soft});
        beginp->addPinsp(new AstConst{fl, AstConst::BitTrue{}, dist});
        beginp->addPinsp(new AstConst{fl, AstConst::BitTrue{}, isEnum});
        AstNodeStmt* const stmtp = beginp->makeStmt();
        for (const Range& range : ranges) {
            AstCMethodHard* const callp = newCallp(fl, VCMethod::RANDOMIZER_FAST_RANGE);
            for (const uint64_t value : {range.lo, range.hi, range.weight, range.divisor}) {
                callp->addPinsp(new AstConst{fl, AstConst::Unsized64{}, value});
            }
            stmtp->addNext(callp->makeStmt());
        }
        return stmtp;
    }
    // A state scalar of the same width can pin a rand scalar without depending
    // on another solve. Copy only a pure leaf, never a function/callback expression.
    AstNodeStmt* newStatePinp(AstConstraintExpr* exprp) const {
        const AstEq* const eqp = VN_CAST(exprp->exprp(), Eq);
        if (!eqp) return nullptr;
        AstNodeExpr* boundp = eqp->rhsp();
        if (!isTarget(eqp->lhsp())) {
            if (!isTarget(eqp->rhsp())) return nullptr;
            boundp = eqp->lhsp();
        }
        const AstVarRef* const refp = VN_CAST(boundp, VarRef);
        if (!refp || refp->user1() || refp->varp()->rand().isRandomizable()
            || boundp->width() != m_varp->width() || eqp->lhsp()->width() != m_varp->width()) {
            return nullptr;
        }
        FileLine* const fl = exprp->fileline();
        AstNodeStmt* const stmtp = newDomainp(fl, {}, exprp->isSoft(), false);
        AstNodeExpr* valuep = boundp->cloneTreePure(false);
        if (m_varp->isSigned()) {
            valuep = new AstXor{fl, valuep,
                                new AstConst{fl, AstConst::WidthedValue{}, m_varp->width(),
                                             uint32_t{1} << (m_varp->width() - 1)}};
        }
        valuep = new AstExtend{fl, valuep, 64};
        AstCMethodHard* const rangep = newCallp(fl, VCMethod::RANDOMIZER_FAST_RANGE);
        rangep->addPinsp(valuep);
        rangep->addPinsp(valuep->cloneTreePure(false));
        rangep->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 1});
        rangep->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 1});
        stmtp->addNext(rangep->makeStmt());
        return stmtp;
    }
    // Pure state leaves can supply runtime bounds/weights without evaluating an
    // arbitrary constraint function or depending on another solve round.
    bool isStateLeaf(const AstNodeExpr* exprp) const {
        const AstVarRef* const refp = VN_CAST(exprp, VarRef);
        return refp && !refp->user1() && !refp->varp()->rand().isRandomizable()
               && !refp->varp()->isStdRandomizeArg()
               && exprp->dtypep()->skipRefp()->isIntegralOrPacked();
    }
    AstNodeExpr* newBoundKeyp(AstNodeExpr* boundp) const {
        FileLine* const fl = boundp->fileline();
        AstNodeExpr* valuep = boundp->cloneTreePure(false);
        if (valuep->width() > m_varp->width()) {
            valuep = new AstSel{fl, valuep, 0, m_varp->width()};
        }
        if (m_varp->isSigned()) {
            valuep = new AstXor{fl, valuep,
                                new AstConst{fl, AstConst::WidthedValue{}, m_varp->width(),
                                             uint32_t{1} << (m_varp->width() - 1)}};
        }
        return new AstExtend{fl, valuep, 64};
    }
    bool isStateBound(const AstNodeExpr* exprp) const {
        if (exprp->width() > 64) return false;
        if (const AstExtend* const extendp = VN_CAST(exprp, Extend))
            exprp = extendp->lhsp();
        else if (const AstExtendS* const extendp = VN_CAST(exprp, ExtendS))
            exprp = extendp->lhsp();
        return isStateLeaf(exprp);
    }
    AstNodeExpr* newLimitComparep(AstNodeExpr* boundp, uint64_t limit, bool less, bool inclusive,
                                  bool isSigned) const {
        FileLine* const fl = boundp->fileline();
        AstNodeExpr* const valuep = boundp->cloneTreePure(false);
        V3Number num{fl, boundp->width()};
        num.setQuad(limit);
        AstConst* const limitp = new AstConst{fl, num};
        if (less) {
            if (inclusive)
                return isSigned ? static_cast<AstNodeExpr*>(new AstLteS{fl, valuep, limitp})
                                : new AstLte{fl, valuep, limitp};
            return isSigned ? static_cast<AstNodeExpr*>(new AstLtS{fl, valuep, limitp})
                            : new AstLt{fl, valuep, limitp};
        }
        if (inclusive)
            return isSigned ? static_cast<AstNodeExpr*>(new AstGteS{fl, valuep, limitp})
                            : new AstGte{fl, valuep, limitp};
        return isSigned ? static_cast<AstNodeExpr*>(new AstGtS{fl, valuep, limitp})
                        : new AstGt{fl, valuep, limitp};
    }
    struct StateInterval final {
        AstNodeExpr* lop;
        AstNodeExpr* hip;
        AstNodeExpr* validp;
        bool hasLower = false;
        bool hasUpper = false;
    };
    // The lowered inside {[lo:hi]} is a conjunction of one lower and one upper
    // comparison. Clamp in the comparison's type before narrowing to SV storage.
    bool stateInterval(AstNodeExpr* exprp, StateInterval& interval) {
        if (AstLogAnd* const andp = VN_CAST(exprp, LogAnd)) {
            return stateInterval(andp->lhsp(), interval) && stateInterval(andp->rhsp(), interval);
        }
        if (!(VN_IS(exprp, Lt) || VN_IS(exprp, Lte) || VN_IS(exprp, Gt) || VN_IS(exprp, Gte)
              || VN_IS(exprp, LtS) || VN_IS(exprp, LteS) || VN_IS(exprp, GtS)
              || VN_IS(exprp, GteS))) {
            return false;
        }
        const AstNodeBiop* const nodep = VN_AS(exprp, NodeBiop);
        AstNodeExpr* boundp = nodep->rhsp();
        bool reversed = false;
        if (!isTarget(nodep->lhsp())) {
            if (!isTarget(nodep->rhsp())) return false;
            boundp = nodep->lhsp();
            reversed = true;
        }
        if (!isStateBound(boundp)) {
            boundp = constant(boundp);
            if (!boundp) return false;
        }
        const bool signedCompare
            = VN_IS(nodep, LtS) || VN_IS(nodep, LteS) || VN_IS(nodep, GtS) || VN_IS(nodep, GteS);
        if (signedCompare != m_varp->isSigned() || boundp->width() < m_varp->width()) return false;
        bool lower
            = VN_IS(nodep, Gt) || VN_IS(nodep, Gte) || VN_IS(nodep, GtS) || VN_IS(nodep, GteS);
        if (reversed) lower = !lower;
        const bool inclusive
            = VN_IS(nodep, Gte) || VN_IS(nodep, Lte) || VN_IS(nodep, GteS) || VN_IS(nodep, LteS);
        FileLine* const fl = exprp->fileline();
        const uint64_t min = signedCompare ? ~((uint64_t{1} << (m_varp->width() - 1)) - 1) : 0;
        const uint64_t max = signedCompare ? (uint64_t{1} << (m_varp->width() - 1)) - 1 : mask();
        if (lower) {
            if (interval.hasLower) return false;
            interval.hasLower = true;
            AstNodeExpr* edgep = newBoundKeyp(boundp);
            if (!inclusive)
                edgep = new AstAdd{fl, edgep, new AstConst{fl, AstConst::Unsized64{}, 1}};
            AstNodeExpr* const clippedp = new AstCond{
                fl, newLimitComparep(boundp, min, true, inclusive, signedCompare),
                new AstConst{fl, AstConst::Unsized64{}, 0},
                new AstCond{fl, newLimitComparep(boundp, max, false, !inclusive, signedCompare),
                            new AstConst{fl, AstConst::Unsized64{}, mask() + 1}, edgep}};
            VL_DO_DANGLING(interval.lop->deleteTree(), interval.lop);
            interval.lop = clippedp;
        } else {
            if (interval.hasUpper) return false;
            interval.hasUpper = true;
            AstNodeExpr* edgep = newBoundKeyp(boundp);
            if (!inclusive)
                edgep = new AstSub{fl, edgep, new AstConst{fl, AstConst::Unsized64{}, 1}};
            AstNodeExpr* const clippedp
                = new AstCond{fl, newLimitComparep(boundp, max, false, inclusive, signedCompare),
                              new AstConst{fl, AstConst::Unsized64{}, mask()}, edgep};
            VL_DO_DANGLING(interval.hip->deleteTree(), interval.hip);
            interval.hip = clippedp;
            VL_DO_DANGLING(interval.validp->deleteTree(), interval.validp);
            interval.validp = newLimitComparep(boundp, min, false, inclusive, signedCompare);
        }
        return true;
    }
    AstNodeStmt* newStateRangep(AstConstraintExpr* exprp) {
        if (!exprp->exprp()->exists([&](const AstVarRef* refp) { return isStateLeaf(refp); })) {
            return nullptr;
        }
        FileLine* const fl = exprp->fileline();
        StateInterval interval{new AstConst{fl, AstConst::Unsized64{}, 0},
                               new AstConst{fl, AstConst::Unsized64{}, mask()},
                               new AstConst{fl, AstConst::BitTrue{}}};
        if (!stateInterval(exprp->exprp(), interval)) {
            VL_DO_DANGLING(interval.lop->deleteTree(), interval.lop);
            VL_DO_DANGLING(interval.hip->deleteTree(), interval.hip);
            VL_DO_DANGLING(interval.validp->deleteTree(), interval.validp);
            return nullptr;
        }
        AstNodeStmt* const stmtp = newDomainp(fl, {}, exprp->isSoft(), false);
        AstCMethodHard* const rangep = newCallp(fl, VCMethod::RANDOMIZER_FAST_RANGE);
        rangep->addPinsp(interval.lop);
        rangep->addPinsp(interval.hip);
        rangep->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 1});
        rangep->addPinsp(new AstConst{fl, AstConst::Unsized64{}, 1});
        stmtp->addNext(new AstIf{fl, interval.validp, rangep->makeStmt()});
        return stmtp;
    }
    AstNodeStmt* newStateDistp(AstConstraintExpr* exprp, AstDist* distp) {
        if (!isTarget(distp->exprp())) return nullptr;
        // Only try this form when there actually is a state leaf. The constant
        // path preserves the existing all-zero-dist policy and validates constants.
        const bool hasState
            = distp->exists([&](const AstVarRef* refp) { return isStateLeaf(refp); });
        if (!hasState) return nullptr;
        FileLine* const fl = exprp->fileline();
        AstNodeStmt* const stmtp = newDomainp(fl, {}, exprp->isSoft(), true);
        bool hasPositiveWeight = false;
        for (AstDistItem* const itemp : distp->itemspList()) {
            const AstInsideRange* const rangeSourcep = VN_CAST(itemp->rangep(), InsideRange);
            AstNodeExpr* lop = rangeSourcep ? rangeSourcep->lhsp() : itemp->rangep();
            AstNodeExpr* hip = rangeSourcep ? rangeSourcep->rhsp() : itemp->rangep();
            AstNodeExpr* weightp = itemp->weightp();
            for (AstNodeExpr** const boundpp : {&lop, &hip, &weightp}) {
                if (isStateLeaf(*boundpp)) continue;
                AstConst* const constp = constant(*boundpp);
                if (!constp) break;
                *boundpp = constp;
            }
            if (!m_supported || lop->width() != m_varp->width() || hip->width() != m_varp->width()
                || weightp->width() > 64) {
                m_supported = false;
                VL_DO_DANGLING(stmtp->deleteTree(), stmtp);
                return nullptr;
            }
            hasPositiveWeight |= isStateLeaf(weightp) || !VN_AS(weightp, Const)->isZero();
            // A negative state weight is not an unsigned probability. Keep the
            // existing solver diagnostics/policy for that invocation.
            if (weightp->isSigned()) {
                AstCMethodHard* const disablep = newCallp(fl, VCMethod::RANDOMIZER_FAST_DISABLE);
                stmtp->addNext(new AstIf{
                    fl,
                    new AstLtS{fl, weightp->cloneTreePure(false),
                               new AstConst{fl, AstConst::WidthedValue{}, weightp->width(), 0}},
                    disablep->makeStmt()});
            }
            AstNodeExpr* const lokeyp = newBoundKeyp(lop);
            AstNodeExpr* const hikeyp = newBoundKeyp(hip);
            AstNodeExpr* const divisorp
                = itemp->isWhole() ? static_cast<AstNodeExpr*>(
                                         new AstAdd{fl,
                                                    new AstSub{fl, hikeyp->cloneTreePure(false),
                                                               lokeyp->cloneTreePure(false)},
                                                    new AstConst{fl, AstConst::Unsized64{}, 1}})
                                   : new AstConst{fl, AstConst::Unsized64{}, 1};
            AstCMethodHard* const rangep = newCallp(fl, VCMethod::RANDOMIZER_FAST_RANGE);
            rangep->addPinsp(lokeyp);
            rangep->addPinsp(hikeyp);
            rangep->addPinsp(new AstExtend{fl, weightp->cloneTreePure(false), 64});
            rangep->addPinsp(divisorp);
            stmtp->addNext(rangep->makeStmt());
        }
        if (!hasPositiveWeight) {
            m_supported = false;  // Constant all-zero weights are ignored by the existing path
            VL_DO_DANGLING(stmtp->deleteTree(), stmtp);
            return nullptr;
        }
        return stmtp;
    }
    AstNodeStmt* build(AstConstraintExpr* exprp) {
        findTarget(exprp->exprp());
        Ranges ranges;
        AstNodeStmt* stmtp = nullptr;
        AstDist* const distp = VN_CAST(exprp->exprp(), Dist);
        if (m_supported && !exprp->isDisableSoft()) {
            stmtp = distp ? newStateDistp(exprp, distp) : newStatePinp(exprp);
            if (!stmtp && !distp && m_supported) stmtp = newStateRangep(exprp);
            if (!stmtp) ranges = distp ? distribution(distp) : parse(exprp->exprp());
        } else
            m_supported = false;
        FileLine* const fl = exprp->fileline();
        if (!m_supported) return newCallp(fl, VCMethod::RANDOMIZER_FAST_DISABLE)->makeStmt();
        if (!stmtp) stmtp = newDomainp(fl, ranges, exprp->isSoft(), distp != nullptr);
        if (const AstEnumDType* const enumDtp
            = VN_CAST(m_varp->dtypep()->skipRefToEnump(), EnumDType)) {
            Ranges enumRanges;
            for (const AstEnumItem* const itemp : enumDtp->itemspList()) {
                const AstConst* const valuep = VN_AS(itemp->valuep(), Const);
                if (valuep->num().isFourState()) continue;
                const uint64_t value = key(valuep->toUQuad());
                enumRanges.push_back({value, value});
            }
            stmtp->addNext(newDomainp(fl, enumRanges, false, false, true));
        }
        V3Stats::addStat("Optimizations, Randomize structured domains", 1);
        return stmtp;
    }
    explicit FastConstraintBuilder(AstVar* genp)
        : m_genp{genp} {}

public:
    ~FastConstraintBuilder() {
        for (AstNodeExpr* const exprp : m_constants) VL_DO_DANGLING(exprp->deleteTree(), exprp);
    }
    static AstNodeStmt* apply(AstNode* itemsp, AstVar* genp, bool allow = true) {
        if (!allow || !v3Global.opt.fConstraintFast() || v3Global.opt.fourstate()) {
            const FastConstraintBuilder builder{genp};
            return builder.newCallp(itemsp->fileline(), VCMethod::RANDOMIZER_FAST_DISABLE)
                ->makeStmt();
        }
        AstNodeStmt* stmtsp = nullptr;
        for (AstNode* const itemp : VNList<AstNode>{itemsp}) {
            FastConstraintBuilder builder{genp};
            AstNodeStmt* const stmtp
                = VN_IS(itemp, ConstraintExpr)
                      ? builder.build(VN_AS(itemp, ConstraintExpr))
                      : builder.newCallp(itemp->fileline(), VCMethod::RANDOMIZER_FAST_DISABLE)
                            ->makeStmt();
            stmtsp = AstNode::addNext(stmtsp, stmtp);
        }
        return stmtsp;
    }
};

//######################################################################
// Visitor that turns constraints into template strings for solvers

class ConstraintExprVisitor final : public VNVisitor {
    // NODE STATE
    // AstVar::user3() -> bool. Handled in constraints
    // AstNodeExpr::user1()    -> bool. Depending on a randomized variable
    // AstMemberRef::user2p()  -> AstNodeModule*. Pointer to containing module
    // VNuser3InUse m_inuser3; (Allocated for use in RandomizeVisitor)

    AstClass* const m_classp;  // Class being processed
    AstBegin* const m_inlineInitBlockp;  // Block to add write_var calls to
                                         // (may be null, then new() is used)
    AstNodeFTask* const m_memberrefInitTaskp;  // Setup of the constraint, for memberref
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
    AstBegin* m_foreachBodyp = nullptr;  // Holder of the body of the innermost constraint-foreach
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
    // Residual guard predicates validate reduction receivers after their iterators are bound.
    bool m_inGuardPredicate = false;
    AstVar* m_foldErrorVarp = nullptr;  // Error status taken over with m_foldTakerp
    // Where the variable references being lowered record their solver names. Set by
    // visit(AstConstraintExpr*), the only visit reaching a variable reference: the other
    // constraint items either move their expressions into one or never iterate them.
    std::set<std::string>* m_constraintVarsp = nullptr;
    // Solver names of the fields of objects in arrays that a constraint payload names,
    // formatted as createWriteVarForClassFields registers them. Collected like
    // m_constraintVars, which has only the names of the arrays.
    struct ElemNames final {
        std::vector<AstNodeExpr*> namesp;  // Field name expressions, owned until used
        void clear() {
            for (AstNodeExpr* namep : namesp) VL_DO_DANGLING(namep->deleteTree(), namep);
            namesp.clear();
        }
    };
    ElemNames m_foldElemNames;  // Of a fold, until its taker takes them over
    ElemNames* m_elemNamesp = nullptr;  // Where the current constraint records them
    bool m_inFuncArg = false;  // Registering the random variables of a function argument
    std::set<std::string> m_funcArgNames;  // Random function arguments in the current item
    std::set<std::string> m_itemVarNames;  // Other random variables in the current item
    std::vector<ConstraintFuncCall> m_funcCalls;  // Items calling functions with random arguments
    // Condition that the arrays reduced in the current constraint keep their current sizes
    AstNodeExpr* m_sizeGatep = nullptr;

    class NestedAccessPath final {
        AstMemberRef* m_topNestedArrayMemberRefp
            = nullptr;  // Top node of nested array/member access
        AstSFormatF* m_nestedNameFormatTopp = nullptr;  // Top node of variable's name format
        AstSFormatF* m_nestedNameFormatp = nullptr;  // Last node of variable's name format
        AstNode** m_firstExpressionInsideIndexPointerp
            = nullptr;  // First expression with no name, used for "Multiple expressions inside
                        // indices of complex expression in constraint" error
        AstNode* m_firstExpressionp = nullptr;  // This path's part recorded there, if any

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
                m_firstExpressionp = nodep;
            }
        }

        AstMemberRef* accessTree() { return m_topNestedArrayMemberRefp; }
        const std::string& smtName() { return m_smtName; }

        AstStmtExpr* makeWriteVarStmt(AstVar* varp, AstVar* genp) {
            AstCMethodHard* const methodp = new AstCMethodHard{
                varp->fileline(),
                new AstVarRef{varp->fileline(), VN_AS(genp->user2p(), NodeModule), genp,
                              VAccess::READWRITE},
                VCMethod::RANDOMIZER_WRITE_VAR};
            methodp->dtypeSetVoid();

            methodp->addPinsp(m_topNestedArrayMemberRefp);  // Variable

            const AstNodeDType* const dtypep = varp->dtypep();  // Width
            const size_t width = m_topNestedArrayMemberRefp->varp()->dtypep()->width();
            methodp->addPinsp(new AstConst{dtypep->fileline(), AstConst::Unsized64{}, width});

            methodp->addPinsp(m_nestedNameFormatTopp);  // Solver name
            m_nestedNameFormatp = nullptr;

            methodp->addPinsp(
                new AstConst{dtypep->fileline(), AstConst::Unsized64{}, 0});  // Dimension

            m_topNestedArrayMemberRefp = nullptr;
            return methodp->makeStmt();
        }

        AstNodeExpr* cloneName() { return m_nestedNameFormatTopp->cloneTree(false); }

        void error() {
            VL_DO_CLEAR(m_topNestedArrayMemberRefp->deleteTree(),
                        m_topNestedArrayMemberRefp = nullptr);
        }

        NestedAccessPath(AstMemberRef* topMemberRefp, AstNode** pointerToFirstExprp)
            : m_topNestedArrayMemberRefp{topMemberRefp}
            , m_firstExpressionInsideIndexPointerp{pointerToFirstExprp} {}
        ~NestedAccessPath() {
            // Not registered, as for a state expression or an already written variable
            if (m_topNestedArrayMemberRefp) {
                VL_DO_DANGLING(m_topNestedArrayMemberRefp->deleteTree(),
                               m_topNestedArrayMemberRefp);
            }
            if (m_nestedNameFormatp) {
                // The recorded part is in the format being freed. This live helper is the only
                // writer of the slot while it exists, and a nested constraint restores the slot
                // before returning, so the slot still holds the part recorded here.
                if (m_firstExpressionp) *m_firstExpressionInsideIndexPointerp = nullptr;
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
        AstStructDType* const structp
            = VN_CAST(RandomizeUtil::arrayElementDTypep(dtypep), StructDType);
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
    // C++ initializer list of the names a soft constraint is disabled by: the solver variables
    // of its payload, and each field of an object in an array named as registered
    static AstCExpr* newSoftVarsListp(FileLine* fl, const std::set<std::string>& vars,
                                      ElemNames& elemNames) {
        // Each field name is followed by a comma, which a braced list allows before its end
        AstCExpr* const listp = new AstCExpr{fl, AstCExpr::Pure{}, "{"};
        for (AstNodeExpr* const namep : elemNames.namesp) {
            listp->add(namep);
            listp->add(", ");
        }
        elemNames.namesp.clear();
        listp->add(constraintVarsList(vars).substr(1));
        return listp;
    }
    // Append to fmt and argsp the solver name of the variable, object field or object exprp
    // selects by state indices, with each object of an array by its index or key as
    // createWriteVarForClassFields and the nested access path register it; false if a part of
    // exprp is not one of these
    static bool addSolverPathFormat(const AstNodeExpr* exprp, std::string& fmt,
                                    AstNodeExpr*& argsp) {
        if (const AstVarRef* const refp = VN_CAST(exprp, VarRef)) {
            fmt += refp->name();
            return true;
        }
        const AstNodeExpr* fromp;
        std::string partFmt;  // Appended after the name of fromp
        AstNodeExpr* indexp = nullptr;  // Index or key the part formats
        const AstCMethodHard* dynSelp = nullptr;  // Element of a dynamic array or queue
        if (const AstMemberRef* const selp = VN_CAST(exprp, MemberRef)) {
            // A member of the object being randomized, named like the payload names it
            if (isCapturedThisSel(selp)) {
                fmt += selp->name();
                return true;
            }
            fromp = selp->fromp();
            partFmt = "." + selp->name();
        } else if (const AstArraySel* const arraySelp = VN_CAST(exprp, ArraySel)) {
            fromp = arraySelp->fromp();
            partFmt = ".%0x";
            indexp = arraySelp->bitp();
        } else if (const AstAssocSel* const assocSelp = VN_CAST(exprp, AssocSel)) {
            fromp = assocSelp->fromp();
            indexp = assocSelp->bitp();
            partFmt = "." + keyHexFormat(indexp->dtypep()->skipRefp());
        } else if (const AstCMethodHard* const atp = VN_CAST(exprp, CMethodHard)) {
            UASSERT_OBJ(atp->method() == VCMethod::ARRAY_AT
                            || atp->method() == VCMethod::ARRAY_AT_BACK,
                        atp, "Selects of a 'disable soft' variable are elements and members");
            fromp = atp->fromp();
            partFmt = "." + keyHexFormat(atp->findUInt32DType());
            indexp = atp->pinsp();
            dynSelp = atp;
        } else {
            return false;
        }
        if (!addSolverPathFormat(fromp, fmt, argsp)) return false;
        fmt += partFmt;
        if (!indexp) return true;
        FileLine* const fl = indexp->fileline();
        AstNodeExpr* idxp = indexp->cloneTreePure(false);
        if (dynSelp) {
            // Registered by a 32-bit index
            if (idxp->width() < 32) {
                idxp = new AstExtend{fl, idxp, 32};
            } else if (idxp->width() > 32) {
                idxp = new AstSel{fl, idxp, 0, 32};
            }
            if (dynSelp->method() == VCMethod::ARRAY_AT_BACK) {
                // As atBack(): of the elements the queue has when its objects are registered
                AstCMethodHard* const sizep = new AstCMethodHard{
                    fl, dynSelp->fromp()->cloneTreePure(false), VCMethod::DYN_SIZE};
                sizep->dtypeSetUInt32();
                idxp = new AstSub{fl, new AstSub{fl, sizep, new AstConst{fl, 1}}, idxp};
            }
        }
        argsp = AstNode::addNextNull(argsp, idxp);
        return true;
    }
    // The call result the select chain of selp selects from, which a constraint_primary does
    // not allow (IEEE 1800-2023 A.1.10), else nullptr; sets randIndex if an element of the chain
    // before it is chosen by a random index or key
    static const AstNodeExpr* findSelCallp(const AstMemberRef* selp, bool& randIndex) {
        for (const AstNodeExpr* exprp = selp->fromp();;) {
            if (const AstMemberRef* const memberSelp = VN_CAST(exprp, MemberRef)) {
                exprp = memberSelp->fromp();
            } else if (const AstStructSel* const structSelp = VN_CAST(exprp, StructSel)) {
                exprp = structSelp->fromp();
            } else if (const AstNodeSel* const nodeSelp = VN_CAST(exprp, NodeSel)) {
                randIndex |= isRandIndex(nodeSelp->bitp());
                exprp = nodeSelp->fromp();
            } else if (const AstCMethodHard* const atp = VN_CAST(exprp, CMethodHard)) {
                if (atp->method() != VCMethod::ARRAY_AT
                    && atp->method() != VCMethod::ARRAY_AT_BACK)
                    return atp;
                randIndex |= isRandIndex(atp->pinsp());
                exprp = atp->fromp();
            } else {
                return VN_IS(exprp, NodeFTaskRef) ? exprp : nullptr;
            }
        }
    }
    // Whether selp is a solver variable field of an object in an array, selected by state
    // indices only, so its solver name is a value fixed before solving
    static bool isStateElemField(const AstMemberRef* selp) {
        bool randIndex = false;
        findSelCallp(selp, randIndex);
        return !VN_IS(selp->dtypep()->skipRefp(), ClassRefDType) && !randIndex;
    }
    // Record the solver name namep formats of an object field, as the payload names it
    void addElemName(const AstNode* nodep, AstNodeExpr* namep) {
        UASSERT_OBJ(m_elemNamesp, nodep, "Object field outside a constraint expression");
        m_elemNamesp->namesp.push_back(namep->cloneTreePure(false));
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

    // Solver name of the element at index 'idxp' of the array named 'namep'. The index is
    // formatted as 32 bits, so as 8 hex digits.
    static AstNodeExpr* newElementNamep(FileLine* fl, AstNodeExpr* namep, AstNodeExpr* idxp) {
        AstNodeExpr* const idx32p
            = adjustWidth(fl, idxp->cloneTreePure(false), 32, VSigning::UNSIGNED);
        AstSFormatF* const hexp = new AstSFormatF{fl, "%x", false, idx32p};
        AstNodeExpr* const prefixp
            = new AstConcatN{fl, namep, new AstConst{fl, AstConst::String{}, "."}};
        return new AstConcatN{fl, prefixp, hexp};
    }

    // Solver name of the variable referenced by the selects and array elements in 'nodep'
    static AstNodeExpr* buildNamePrefix(FileLine* fl, const AstNodeExpr* const nodep) {
        if (const AstVarRef* const refp = VN_CAST(nodep, VarRef)) {
            return new AstConst{fl, AstConst::String{}, refp->name()};
        }

        // Empty if not rooted in a variable, as under an unsupported MemberRef reported below
        const AstNodeExpr* const fromp = getFromp(nodep);
        AstNodeExpr* const namep
            = fromp ? buildNamePrefix(fl, fromp) : new AstConst{fl, AstConst::String{}, ""};

        // A member of a member object chain (e.g. 'r.c.x' in a global constraint) is
        // registered with its dotted path, as a struct member is
        if (VN_IS(nodep, StructSel)
            || (VN_IS(nodep, MemberRef) && (VN_IS(fromp, VarRef) || VN_IS(fromp, MemberRef)))) {
            return new AstConcatN{fl, namep,
                                  new AstConst{fl, AstConst::String{}, "." + nodep->name()}};
        } else if (VN_IS(nodep, MemberRef)) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: Nested array element access in global constraint");
        } else if (const AstCMethodHard* const cmethp = VN_CAST(nodep, CMethodHard)) {
            UASSERT_OBJ(cmethp->method() == VCMethod::ARRAY_AT, cmethp,
                        "Unexpected CMethodHard: " << cmethp->prettyTypeNameQ());
            return newElementNamep(fl, namep, cmethp->pinsp());
        }
        return namep;
    }

    // Solver name of a solve-before variable reference, as a string expression.
    // Handles simple vars, struct selects, and array element selects (for foreach).
    static AstNodeExpr* buildPathExpr(FileLine* const fl, const AstNodeExpr* nodep,
                                      const std::string selName) {
        AstNodeExpr* const namep = buildNamePrefix(fl, nodep);
        if (selName.empty()) return namep;
        return new AstConcatN{fl, namep, new AstConst{fl, AstConst::String{}, "." + selName}};
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
    // Solver name of element select selp (see elemSelFromp), nullptr if unsupported
    static AstNodeExpr* buildArraySelNameExpr(FileLine* fl, const AstNodeExpr* selp) {
        AstNodeExpr* indexp = nullptr;
        AstNodeExpr* const fromp = elemSelFromp(selp, indexp);
        AstNodeExpr* fromIndexp = nullptr;
        AstNodeExpr* prefixp = nullptr;  // Name of the array
        if (elemSelFromp(fromp, fromIndexp)) {
            prefixp = buildArraySelNameExpr(fl, fromp);  // Of a multi-dimensional array
        } else if (const AstVarRef* const vp = VN_CAST(fromp, VarRef)) {
            prefixp = new AstConst{fl, AstConst::String{}, vp->name()};
        } else if (const AstMemberRef* const mp = VN_CAST(fromp, MemberRef)) {
            prefixp = new AstConst{fl, AstConst::String{}, buildMemberPath(mp)};
        }
        if (!prefixp) return nullptr;
        return newElementNamep(fl, prefixp, indexp);
    }

    // Helper: get fromp from MemberRef or StructSel
    static AstNodeExpr* getSelFromp(const AstNodeExpr* exprp) {
        if (const AstMemberRef* const memberRefp = VN_CAST(exprp, MemberRef))
            return memberRefp->fromp();
        if (const AstStructSel* const sp = VN_CAST(exprp, StructSel)) return sp->fromp();
        return nullptr;
    }

    // Solver name of a solve-before variable reference, as a string expression.
    // Returns nullptr for unsupported expression types.
    AstNodeExpr* buildSolveBeforeNameExpr(FileLine* fl, AstNodeExpr* exprp) {
        if (const AstVarRef* const varrefp = VN_CAST(exprp, VarRef)) {
            return new AstConst{fl, AstConst::String{}, varrefp->name()};
        }
        // Handle MemberRef or StructSel (V3Width converts MemberRef -> StructSel for structs)
        if (AstNodeExpr* const selFromp = getSelFromp(exprp)) {
            const std::string selName = exprp->name();
            // Check if fromp chain contains ArraySel (e.g., cfg[i].w)
            if (const AstArraySel* const arrSelp = VN_CAST(selFromp, ArraySel)) {
                return buildArraySelNameExpr(fl, arrSelp);
            }
            // Static member path (obj.field)
            if (const AstVarRef* const vp = VN_CAST(selFromp, VarRef)) {
                return new AstConst{fl, AstConst::String{}, vp->name() + "." + selName};
            }
            if (VN_IS(selFromp, MemberRef) || VN_IS(selFromp, StructSel)
                || VN_IS(selFromp, CMethodHard)) {
                return buildPathExpr(fl, selFromp, selName);
            }
            return nullptr;
        }
        if (VN_IS(exprp, CMethodHard)) return buildPathExpr(fl, exprp, "");
        const AstNodeSel* selp = VN_CAST(exprp, ArraySel);
        if (!selp) selp = VN_CAST(exprp, AssocSel);
        if (selp) return buildArraySelNameExpr(fl, selp);  // arr[i] -> dynamic name
        return nullptr;
    }
    // Add the solver name, lsb and width (0 for all bits) of solve-before operand 'exprp'
    void addSolveBeforePins(AstCMethodHard* const callp, AstNodeExpr* exprp) {
        // A packed struct member or another part of a variable or array element is a select,
        // possibly of a select
        FileLine* const fl = exprp->fileline();
        AstNodeExpr* lsbp = nullptr;
        AstNodeExpr* validp = nullptr;  // Whether each select of a select is in its range
        uint32_t width = 0;
        while (const AstSel* const selp = VN_CAST(exprp, Sel)) {
            AstNodeExpr* partLsbp = selp->lsbp()->cloneTreePure(false);
            if (partLsbp->width() < 32) partLsbp = new AstExtend{fl, partLsbp, 32};
            // The runtime checks the select of the variable or element, not one of a select,
            // which out of range would select bits next to that select
            if (const AstSel* const fromSelp = VN_CAST(selp->fromp(), Sel)) {
                AstNodeExpr* const inRangep
                    = new AstLte{fl, partLsbp->cloneTreePure(false),
                                 new AstConst{fl, static_cast<uint32_t>(fromSelp->widthConst()
                                                                        - selp->widthConst())}};
                validp = validp ? new AstLogAnd{fl, validp, inRangep} : inRangep;
            }
            lsbp = lsbp ? new AstAdd{fl, lsbp, partLsbp} : partLsbp;
            if (!width) width = selp->widthConst();
            exprp = selp->fromp();
        }
        // An lsb past the end of any variable, which the runtime does not order
        if (validp) lsbp = new AstCond{fl, validp, lsbp, new AstConst{fl, ~0U}};
        AstNodeExpr* const namep = buildSolveBeforeNameExpr(fl, exprp);
        UASSERT_OBJ(namep, exprp, "Unexpected expression type in solve...before");
        callp->addPinsp(namep);
        callp->addPinsp(lsbp ? lsbp : new AstConst{fl, 0});
        callp->addPinsp(new AstConst{fl, width});
    }

    bool editFormat(AstNodeExpr* nodep) {
        if (nodep->user1()) return editStateArraySel(nodep);
        // Replace computable expression with SMT constant
        VNRelinker handle;
        nodep->unlinkFrBack(&handle);
        handle.relink(m_inGuardPredicate ? formatStateGuardValue(nodep) : getConstFormat(nodep));
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
            AstBegin* const tempp = SmtUtil::newItemsHolderp(fl, itemsp->unlinkFrBackWithNext());
            VL_DO_DANGLING(iterateAndNextNull(tempp->declsp()), itemsp);
            itemsp = tempp->declsp();
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
            } else if (const AstMemberRef* const selp = VN_CAST(exprp, MemberRef)) {
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
        if (!VN_IS(nodep, NodeVarRef) && !VN_IS(nodep, MemberRef)) nodep->user1(randOperand);
        return nodep->user1();
    }

    // Convert expression to target width using extend or truncate as needed
    static AstNodeExpr* adjustWidth(FileLine* fl, AstNodeExpr* exprp, int targetWidth,
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
        AstVar* const retVarp = funcp->fvarp();
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
            while (AstMemberRef* const selp = VN_CAST(leafp->backp(), MemberRef)) {
                leafp = selp;
                random |= selp->user1();
            }
            if (const AstMemberRef* const selp = VN_CAST(leafp, MemberRef)) {
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
    // bucket draw is evaluated in the same scope as its references.
    static AstNodeStmt* prependDistPreamble(AstConstraintForeach* nodep, AstNodeStmt* bodyp) {
        AstNodeStmt* const preamblep = VN_AS(nodep->user3p(), NodeStmt);
        if (!preamblep) return bodyp;
        nodep->user3p(nullptr);
        preamblep->addNext(bodyp);
        return preamblep;
    }

    // Constraint text over the elements of an array is built at run time, by a loop
    // appending to a string variable.

    // Variable the text is built in
    static AstVar* newTextVarp(AstNode* nodep) {
        AstVar* const varp = new AstVar{nodep->fileline(), VVarType::BLOCKTEMP, "__Vtext",
                                        nodep->findStringDType()};
        varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        return varp;
    }
    // Statement appending 'exprp' to the text in 'varp'
    static AstStmtExpr* newTextAppendp(FileLine* flp, AstVar* varp, AstNodeExpr* exprp) {
        AstCFuncHard* const callp = new AstCFuncHard{flp, VCFunction::STRING_APPEND,
                                                     new AstVarRef{flp, varp, VAccess::READWRITE}};
        callp->addPinsp(exprp);
        callp->dtypeSetVoid();
        return callp->makeStmt();
    }
    // Statement appending a space and the term 'termp' to the text in 'varp'
    static AstStmtExpr* newTermAppendp(FileLine* flp, AstVar* varp, AstNodeExpr* termp) {
        return newTextAppendp(
            flp, varp, new AstConcatN{flp, new AstConst{flp, AstConst::String{}, " "}, termp});
    }
    // The SMT operator 'op' applied to the terms in 'varp', or 'identity' if there are none
    static AstCond* newTextApplyp(FileLine* flp, AstVar* varp, const std::string& op,
                                  const std::string& identity) {
        AstNodeExpr* const isEmptyp = new AstEqN{flp, new AstVarRef{flp, varp, VAccess::READ},
                                                 new AstConst{flp, AstConst::String{}, ""}};
        AstNodeExpr* const openp
            = new AstConcatN{flp, new AstConst{flp, AstConst::String{}, "(" + op},
                             new AstVarRef{flp, varp, VAccess::READ}};
        AstNodeExpr* const appliedp
            = new AstConcatN{flp, openp, new AstConst{flp, AstConst::String{}, ")"}};
        return new AstCond{flp, isEmptyp, new AstConst{flp, AstConst::String{}, identity},
                           appliedp};
    }
    // The text the statements of blockp return with AstCReturn, as an expression. Each
    // return becomes an assignment of a text variable, and the statements after a
    // conditional return become the else branch of the conditional.
    AstSFormatF* newReturnedTextp(FileLine* fl, AstBegin* blockp) {
        AstVar* const textVarp = newTextVarp(blockp);
        blockp->addDeclsp(textVarp);
        lowerTextReturns(blockp->stmtsp(), textVarp);
        return new AstSFormatF{
            fl, "%s", false,
            new AstExprStmt{fl, blockp, new AstVarRef{fl, textVarp, VAccess::READ}}};
    }
    // Make each AstCReturn in the linked statements from stmtp on assign textVarp instead,
    // see newReturnedTextp
    static void lowerTextReturns(AstNodeStmt* stmtsp, AstVar* const textVarp) {
        for (AstNodeStmt* const stmtp : VNList<AstNodeStmt>{stmtsp}) {
            if (AstCReturn* const returnp = VN_CAST(stmtp, CReturn)) {
                UASSERT_OBJ(!returnp->nextp(), returnp, "Statement after return");
                FileLine* const fl = returnp->fileline();
                returnp->replaceWith(new AstAssign{fl, new AstVarRef{fl, textVarp, VAccess::WRITE},
                                                   returnp->lhsp()->unlinkFrBack()});
                VL_DO_DANGLING(returnp->deleteTree(), returnp);
                return;
            }
            AstIf* const ifp = VN_CAST(stmtp, If);
            if (!ifp || !ifp->thensp() || !VN_IS(ifp->thensp()->lastp(), CReturn)) continue;
            lowerTextReturns(ifp->thensp(), textVarp);
            // The statements after the conditional return only run when it does not
            if (AstNodeStmt* const restp = VN_AS(ifp->nextp(), NodeStmt)) {
                UASSERT_OBJ(!ifp->elsesp(), ifp, "Statement after returns in both branches");
                ifp->addElsesp(restp->unlinkFrBackWithNext());
            }
            lowerTextReturns(ifp->elsesp(), textVarp);
            return;
        }
    }
    // The text 'resultp', after 'foreachp' built it in 'varp', starting from 'init'
    AstSFormatF* newTextBuildp(FileLine* flp, AstVar* varp, const std::string& init,
                               AstForeach* foreachp, AstNodeExpr* resultp) {
        AstBegin* const blockp
            = new AstBegin{flp, m_uniqueNames.get("__VrandBlock"), nullptr, true};
        blockp->addDeclsp(varp);
        blockp->addStmtsp(new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE},
                                        new AstConst{flp, AstConst::String{}, init}});
        blockp->addStmtsp(foreachp);
        return new AstSFormatF{flp, "%s", false, new AstExprStmt{flp, blockp, resultp}};
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
    void addRegistrationStmt(AstNodeStmt* const stmtp, AstBegin* const initp) {
        if (m_foreachBodyp && referencesForeachIdx(stmtp)) {
            // Appending to the body mid-iteration is safe: visit(AstNodeStmt) is a
            // no-op so the appended node is not re-processed, and prependDistPreamble()
            // correctly keeps it as a loop-body statement.
            m_foreachBodyp->addDeclsp(stmtp);
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
        AstVar* const textVarp = newTextVarp(selp);
        // Each element stores its value in the array built so far
        AstNodeStmt* bodyp
            = new AstAssign{fl, new AstVarRef{fl, textVarp, VAccess::WRITE},
                            new AstConcatN{fl, new AstConst{fl, AstConst::String{}, "(store "},
                                           new AstVarRef{fl, textVarp, VAccess::READ}}};
        bodyp->addNext(newTermAppendp(
            fl, textVarp,
            getConstFormat(posp->width() < idxWidth ? new AstExtend{fl, posp, idxWidth} : posp)));
        bodyp->addNext(
            newTermAppendp(fl, textVarp, VN_AS(iterateSubtreeReturnEdits(elemp), NodeExpr)));
        bodyp->addNext(newTextAppendp(fl, textVarp, new AstConst{fl, AstConst::String{}, ")"}));
        if (nonNullp) bodyp = new AstIf{fl, nonNullp, bodyp};
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
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VrandBlock"), nullptr, true};
        blockp->addDeclsp(textVarp);
        blockp->addStmtsp(
            new AstAssign{fl, new AstVarRef{fl, textVarp, VAccess::WRITE},
                          new AstConst{fl, AstConst::String{},
                                       "((as const (Array (_ BitVec " + cvtToStr(idxWidth)
                                           + ") (_ BitVec " + cvtToStr(width) + "))) "}});
        blockp->addStmtsp(newTextAppendp(fl, textVarp, getConstFormat(defaultp)));
        blockp->addStmtsp(newTextAppendp(fl, textVarp, new AstConst{fl, AstConst::String{}, ")"}));
        blockp->addStmtsp(new AstForeach{fl, headerp, bodyp});
        return new AstSFormatF{
            fl, "%s", false,
            new AstExprStmt{fl, blockp, new AstVarRef{fl, textVarp, VAccess::READ}}};
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
        AstNodeExpr* const selp = RandomizeUtil::randIndexSelp(nodep, isRandIndex);
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
    void addMemberRefRegistration(AstNodeStmt* regp, AstVar* const varp,
                                  AstMemberRef* const memberRefp, const std::string& smtName,
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
        AstNodeExpr* activep = newHandlesActivep(m_memberMap, memberRefp->fromp(), true, false);
        AstVar* const subRandModeVarp
            = RandModeVars::randModeVarp(VN_AS(varp->user2p(), NodeModule));
        if (randMode.usesMode && subRandModeVarp) {
            AstMemberRef* const randModeSelp
                = new AstMemberRef{fl, memberRefp->fromp()->cloneTree(false), subRandModeVarp};
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
            = newHandlesActivep(m_memberMap, memberRefp->fromp(), false, true)) {
            regp = new AstIf{fl, nonNullp, regp, newGenCallp(VCMethod::RANDOMIZER_CLEAR_VAR)};
        }
        addRegistrationStmt(regp, initp);
    }

    void markRandc(AstVar* const varp, const std::string& smtName, AstBegin* const initp) {
        // The randomizer records the used values of a randc variable as 64-bit numbers
        const int width = RandomizeUtil::arrayElementDTypep(varp->dtypep())->width();
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

    AstNodeModule* getLeftmostVarModulep(AstMemberRef* const memberRefp,
                                         AstVar* const varp) const {
        if (memberRefp) {
            // For memberRefp, find the leftmost varref to get the class
            AstNode* leftMostNodep = memberRefp->fromp();
            while (AstMemberRef* const nestedMemberRefp = VN_CAST(leftMostNodep, MemberRef)) {
                leftMostNodep = nestedMemberRefp->fromp();
            }
            if (AstNodeVarRef* const rootVarRefp = VN_CAST(leftMostNodep, NodeVarRef)) {
                return VN_AS(rootVarRefp->varp()->user2p(), NodeModule);
            }
            return VN_AS(memberRefp->user2p(), NodeModule);
        }
        return VN_AS(varp->user2p(), NodeModule);
    }

    AstBegin* getInitp(AstVar* const varp, const bool memberrefOrStructSel,
                       AstNodeModule* const classp) const {
        if (m_inlineInitBlockp) return m_inlineInitBlockp;
        varp->user3(true);
        if (memberrefOrStructSel) {
            // Not in new(), as the selected object may not exist yet. In the setup of the
            // constraint, as every class solving the constraint runs it.
            UASSERT_OBJ(m_memberrefInitTaskp, varp, "No setup task for the constraint");
            return newInitBlockp(m_memberrefInitTaskp);
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
        AstNodeStmt* enablesp = nullptr;  // While activep, written back
        AstNodeStmt* disablesp = nullptr;  // Otherwise not

        foreachSolverElemField(elemClassp, [&](AstVar* const memberVarp) {
            const int memberWidth = memberVarp->dtypep()->skipRefp()->width();

            AstNodeExpr* const arrayWrRefp = arrayRefp->cloneTree(false);
            if (AstVarRef* const varRefp = VN_CAST(arrayWrRefp, VarRef)) {
                varRefp->access(VAccess::WRITE);
            } else {
                VN_AS(arrayWrRefp, MemberRef)->access(VAccess::WRITE);
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
            AstMemberRef* const memberSelp = new AstMemberRef{fl, atWritep, memberVarp};

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
        AstNodeStmt* stmtsp
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
            UASSERT_OBJ(m_memberrefInitTaskp, varp, "No randomize() to register array in");
            initp = newInitBlockp(m_memberrefInitTaskp);
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
            AstNodeStmt* const firstStmtp = firstp->makeStmt();
            stmtsp = AstNode::addNext(firstStmtp, stmtsp);
            loopp->addStmtsp(nextp->makeStmt());
        }
        initp->addStmtsp(clearp->makeStmt());
        initp->addStmtsp(nonNullp ? new AstIf{fl, nonNullp, stmtsp} : stmtsp);
    }

    void createSolverVarHandle(AstVar* const varp, const bool structSelOrCMeth,
                               const bool isGlobalConstrained, const RandomizeMode randMode,
                               AstMemberRef* const memberRefp, const std::string& smtName,
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
        if (memberRefp) {
            methodp->addPinsp(memberRefp);
        } else {
            AstVarRef* const varRefp
                = new AstVarRef{varp->fileline(), classp, varp, VAccess::WRITE};
            varRefp->classOrPackagep(classOrPackagep);
            methodp->addPinsp(varRefp);
        }
        const size_t width = RandomizeUtil::arrayElementDTypep(varp->dtypep())->width();
        methodp->addPinsp(new AstConst{varp->fileline(), AstConst::Unsized64{}, width});
        AstNodeExpr* const varnamep = new AstCExpr{varp->fileline(), AstCExpr::Pure{},
                                                   "\"" + smtName + "\"", varp->width()};
        varnamep->dtypep(varp->dtypep());
        methodp->addPinsp(varnamep);
        methodp->addPinsp(
            new AstConst{varp->dtypep()->fileline(), AstConst::Unsized64{}, unpackedDims});
        if (randMode.usesMode && !(isGlobalConstrained && memberRefp)) {
            methodp->addPinsp(
                new AstConst{varp->fileline(), AstConst::Unsized64{}, randMode.index});
        }
        // For globalConstrained sub-object members with rand_mode:
        // Always call write_var (keeps variable in solver for constraint
        // evaluation), but toggle disabled state so the solver skips
        // write-back when rand_mode is off.
        if (memberRefp) {
            addMemberRefRegistration(methodp->makeStmt(), varp, memberRefp, smtName,
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
                                AstMemberRef* memberRefp, AstVar* const varp) {
        // Use AstSFormatF (not AstConst{String}) to prevent editFormat/V3Const
        // from reformatting the SMT variable name into a hex literal
        AstNodeExpr* exprp = new AstSFormatF{
            nodep->fileline(), m_nestedAccessp ? nodep->name() : smtName, false, nullptr};
        // A variable of the object of an inactive handle is a state variable. The objects of
        // a handle array are checked where their fields are selected.
        // rand_mode() only affects rand variables, so not the size variable of an array of
        // the object, which is pinned instead.
        const bool classHandleArray = RandomizeUtil::isClassHandleArray(varp);
        AstNodeExpr* const handlesActivep
            = memberRefp && !classHandleArray && varp->rand().isRandomizable()
                  ? newHandlesActivep(m_memberMap, memberRefp->fromp(), true, false)
                  : nullptr;
        if ((!randMode.usesMode || classHandleArray) && !handlesActivep) {
            // Global constraints keep nodep alive for write_var processing
            if (!isGlobalConstrained) VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return exprp;
        }

        // Get const format, using memberRefp if available for correct width/value
        AstNodeExpr* constFormatp = newStateFormatp(memberRefp ? memberRefp->cloneTree(false)
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
        } else if (memberRefp) {
            AstNodeModule* const varClassp = VN_AS(varp->user2p(), NodeModule);
            AstVar* const effectiveRandModeVarp = RandModeVars::randModeVarp(varClassp);
            if (effectiveRandModeVarp) {
                // Member's class has randmode, use it
                AstNodeExpr* parentAccessp = memberRefp->fromp()->cloneTree(false);
                AstMemberRef* randModeRefp
                    = new AstMemberRef{varp->fileline(), parentAccessp, effectiveRandModeVarp};
                randModeRefp->dtypep(effectiveRandModeVarp->dtypep());
                randModeAccessp = randModeRefp;
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
    static bool isCapturedThisSel(const AstMemberRef* selp) {
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

        AstMemberRef* memberRefp = nullptr;
        bool structSelOrCMeth = false;
        // Set below only when narrowing to one struct field/array element;
        // staying null means "check varp's own type" (see its use further down).
        AstNodeDType* selectedDtypep = nullptr;
        std::string smtName;
        if (m_nestedAccessp) {
            m_nestedAccessp->addVarNamePart(
                new AstSFormatF{varp->fileline(), nodep->name(), false, nullptr}, nodep->name());
            smtName = m_nestedAccessp->smtName();
            memberRefp = m_nestedAccessp->accessTree();
        } else if (VN_IS(nodep->backp(), MemberRef)) {
            // Build complete path from topmost MemberRef
            AstNode* topMemberRefp = nodep->backp();
            while (VN_IS(topMemberRefp->backp(), MemberRef)) {
                topMemberRefp = topMemberRefp->backp();
            }
            memberRefp = VN_AS(topMemberRefp, MemberRef)->cloneTree(false);
            smtName = buildMemberPath(memberRefp);
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

            memberRefp = VN_CAST(topNodep, MemberRef);
            if (memberRefp) smtName = buildMemberPath(memberRefp);

            // Above functions returned empty string, unrecognized node type,
            // Using nodep->name();
            if (smtName == "") smtName = nodep->name();
        } else {
            // No MemberRef, StructSel or CMethodHard:at : just variable name
            smtName = nodep->name();
        }
        // Recorded so the runtime can tell constraints naming only randc variables apart
        // (#8058). A name matching no registered variable, as a nested access path formatted
        // at runtime does, must be taken as a non-randc variable, so its constraint is never
        // randc-only.
        UASSERT_OBJ(m_constraintVarsp, nodep,
                    "Variable reference outside a constraint expression");
        if (nodep->user1()) m_constraintVarsp->insert(smtName);

        if (memberRefp) varp = memberRefp->varp();
        // The SMT translation assumes bit-vector operands and does not
        // type-check; embedding a real value produces a malformed width.
        // Check the selected field/element's type, not the whole
        // struct/array's -- a real sibling field elsewhere is irrelevant.
        if (SmtUtil::dtypeContainsReal(structSelOrCMeth ? selectedDtypep : varp->dtypep())) {
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
            = createVarExprp(nodep, randMode, smtName, isGlobalConstrained, memberRefp, varp);
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
        const bool perClass = isGlobalConstrained || memberRefp || isClassRefArray;
        // A path through a runtime index is named by the index's expression, not the element,
        // so it is registered at each reference, in its own loop; write_var() ignores repeats
        const bool runtimeIndexPath = memberRefp && memberRefp->exists([](const AstNode* selp) {
            if (const AstArraySel* const arraySelp = VN_CAST(selp, ArraySel)) {
                return !VN_IS(arraySelp->bitp(), Const);
            }
            if (const AstAssocSel* const assocSelp = VN_CAST(selp, AssocSel)) {
                return !VN_IS(assocSelp->bitp(), Const);
            }
            // Other methods on the path make it state, and a method in an index is under a select
            // seen first, so a method here is an element select
            const AstCMethodHard* const atp = VN_CAST(selp, CMethodHard);
            return atp && !VN_IS(atp->pinsp(), Const);
        });
        const bool alreadyWritten = m_inlineInitBlockp ? m_inlineWrittenVars.count(smtName) > 0
                                    : perClass         ? m_writtenVars.count(smtName) > 0
                                                       : !m_newWrittenVarsp->insert(varp).second;
        const bool shouldWriteVar = runtimeIndexPath || !alreadyWritten;
        if (shouldWriteVar) {
            // Track this variable path as written
            if (m_inlineInitBlockp)
                m_inlineWrittenVars.insert(smtName);
            else if (perClass)
                m_writtenVars.insert(smtName);
            // For global constraints, delete nodep after processing
            if (isGlobalConstrained && !nodep->backp()) VL_DO_DANGLING(pushDeletep(nodep), nodep);

            if (isClassRefArray && !m_nestedAccessp) {
                AstNodeExpr* arrayRefp = memberRefp;
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
            AstNodeModule* const classp = getLeftmostVarModulep(memberRefp, varp);
            const bool inRandomize = memberRefp || structSelOrCMeth;
            AstBegin* const initp = getInitp(varp, inRandomize, classp);
            if (m_nestedAccessp) {
                AstStmtExpr* const writeVarStmtp = m_nestedAccessp->makeWriteVarStmt(varp, m_genp);
                addMemberRefRegistration(writeVarStmtp, varp, memberRefp, smtName,
                                         isGlobalConstrained ? randMode : RandomizeMode{}, initp);
                // If randc, also emit markRandc() for cyclic tracking
                if (varp->isRandC()) markRandc(varp, smtName, initp);
            } else if (isMultiDimHandleArray(varp->dtypep())) {
                exprp->v3warn(E_UNSUPPORTED, "Unsupported: Constraint referencing a"
                                             " multi-dimensional array of class handles");
                if (memberRefp) VL_DO_DANGLING(memberRefp->deleteTree(), memberRefp);
            } else {
                createSolverVarHandle(varp, structSelOrCMeth, isGlobalConstrained, randMode,
                                      memberRefp, smtName, classOrPackagep, classp, initp);
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
            // Variable already written, clean up cloned memberRefp if any; a nested access
            // path's own is freed with it
            if (memberRefp && !m_nestedAccessp) {
                VL_DO_DANGLING(memberRefp->deleteTree(), memberRefp);
            }
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
            // Always visit the wrapper: a rand MemberRef can have user1 unset until its
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
        blockp->addDeclsp(varp);
        return varp;
    }
    // Block holding expression exprp while its receivers are edited, as a declaration since it
    // is not a statement
    static AstBegin* newGuardReadWrapperp(FileLine* const fl, AstNodeExpr* const exprp) {
        AstBegin* const wrapperp = new AstBegin{fl, "[GuardRead]", nullptr, false};
        wrapperp->addDeclsp(exprp);
        return wrapperp;
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
    static bool isStateReductionWith(const AstCMethodHard* const nodep) {
        const VCMethod method = nodep->method();
        return !nodep->user1() && nodep->withp()
               && (method == VCMethod::ARRAY_R_SUM || method == VCMethod::ARRAY_R_PRODUCT
                   || method == VCMethod::ARRAY_R_AND || method == VCMethod::ARRAY_R_OR
                   || method == VCMethod::ARRAY_R_XOR);
    }
    // Native STATE reductions keep checks in the callback that binds their iterators.
    GuardRead sampleNativeGuardWith(AstWith* const withp, AstVar* const errorVarp) {
        FileLine* const fl = withp->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardWith"), nullptr, true};
        AstBegin* const wrapperp
            = newGuardReadWrapperp(fl, VN_AS(withp->exprp()->unlinkFrBack(), NodeExpr));
        const GuardRead read
            = editGuardReceivers(wrapperp->declsp(), blockp, errorVarp, true, true);
        AstNodeExpr* const exprp = VN_AS(wrapperp->declsp()->unlinkFrBack(), NodeExpr);
        VL_DO_DANGLING(wrapperp->deleteTree(), wrapperp);
        if (!read.sampled) {
            withp->addExprp(exprp);
            VL_DO_DANGLING(blockp->deleteTree(), blockp);
            return read;
        }
        AstVar* const valueVarp = newGuardVarp(fl, blockp, withp->dtypep());
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::DTyped{}, withp->dtypep()}});
        blockp->addStmtsp(
            new AstIf{fl, newNoGuardErrorp(errorVarp),
                      new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE), exprp}});
        withp->addExprp(new AstExprStmt{fl, blockp, newGuardRefp(valueVarp)});
        return read;
    }
    // Move receivers out of one cloned leaf in postorder. Every prefix is sampled once;
    // neither prefix scans nor cloning a prefix at every member selection are necessary.
    GuardRead editGuardReceivers(AstNode* const nodep, AstBegin* const blockp,
                                 AstVar* const errorVarp, const bool boundIterators = false,
                                 const bool nativeCallbacks = false) {
        FileLine* const fl = nodep->fileline();
        if (AstCond* const condp = VN_CAST(nodep, Cond)) {
            const bool stateCond = !condp->condp()->user1();
            const bool stateValue = !condp->user1();
            GuardRead result = editGuardReceivers(condp->condp(), blockp, errorVarp,
                                                  boundIterators, nativeCallbacks);
            if (!stateCond || result.unresolved) {
                // The selected arm cannot be sampled before the condition is bound/solved.
                result.unresolved = true;
                return result;
            }
            AstBegin* const thenBlockp
                = new AstBegin{fl, m_uniqueNames.get("__VguardThen"), nullptr, true};
            AstBegin* const elseBlockp
                = new AstBegin{fl, m_uniqueNames.get("__VguardElse"), nullptr, true};
            const GuardRead thenRead = editGuardReceivers(condp->thenp(), thenBlockp, errorVarp,
                                                          boundIterators, nativeCallbacks);
            const GuardRead elseRead = editGuardReceivers(condp->elsep(), elseBlockp, errorVarp,
                                                          boundIterators, nativeCallbacks);
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
        if (nativeCallbacks) {
            if (AstCMethodHard* const methodp = VN_CAST(nodep, CMethodHard)) {
                if (isStateReductionWith(methodp)) {
                    GuardRead result = editGuardReceivers(methodp->fromp(), blockp, errorVarp,
                                                          boundIterators, nativeCallbacks);
                    const GuardRead body = sampleNativeGuardWith(methodp->withp(), errorVarp);
                    result.unresolved |= body.unresolved;
                    result.sampled |= body.sampled;
                    result.checked |= body.checked;
                    return result;
                }
            }
        }
        AstNodeExpr* fromp = nullptr;
        if (AstMemberRef* const selp = VN_CAST(nodep, MemberRef)) {
            fromp = selp->fromp();
        } else if (AstMethodCall* const callp = VN_CAST(nodep, MethodCall)) {
            fromp = callp->fromp();
        }
        bool fromUnresolved = false;
        GuardRead result;
        for (AstNode* const opp : {nodep->op1p(), nodep->op2p(), nodep->op3p(), nodep->op4p()}) {
            for (AstNode *childp = opp, *nextp; childp; childp = nextp) {
                nextp = childp->nextp();
                const GuardRead child = editGuardReceivers(childp, blockp, errorVarp,
                                                           boundIterators, nativeCallbacks);
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
        } else if (VN_IS(nodep, LambdaArgRef)) {
            // Native with callbacks already bind iterators; SMT binding occurs later.
            result.unresolved |= !boundIterators;
        }
        // The child's root may have become a sampled conditional value.
        if (AstMemberRef* const selp = VN_CAST(nodep, MemberRef)) {
            fromp = selp->fromp();
        } else if (AstMethodCall* const callp = VN_CAST(nodep, MethodCall)) {
            fromp = callp->fromp();
        }
        if (fromp && fromp->isClassHandleValue() && !fromUnresolved) {
            AstVar* const receiverVarp = newGuardVarp(fl, blockp, fromp->dtypep());
            fromp->replaceWith(newGuardRefp(receiverVarp));
            AstNodeStmt* const samplep
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
        AstBegin* const wrapperp = newGuardReadWrapperp(fl, exprp->cloneTree(false));
        const GuardRead read
            = editGuardReceivers(wrapperp->declsp(), blockp, errorVarp, false, !exprp->user1());
        AstNodeExpr* const valuep = VN_AS(wrapperp->declsp()->unlinkFrBack(), NodeExpr);
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
        AstNodeExpr* sampledValuep = valuep;
        if (errorp) {
            // Native reductions may set ERROR during evaluation. Neither truth proof may be
            // assigned until the complete leaf has been evaluated and its status rechecked.
            AstVar* const valueVarp = newGuardVarp(fl, blockp, valuep->dtypep());
            blockp->addStmtsp(
                new AstIf{fl, newNoGuardErrorp(errorVarp),
                          new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE), valuep}});
            sampledValuep = newGuardRefp(valueVarp);
        }
        AstNodeStmt* samplep = new AstAssign{fl, newGuardRefp(trueVarp, VAccess::WRITE),
                                             new AstLogNot{fl, new AstLogNot{fl, sampledValuep}}};
        samplep->addNext(new AstAssign{fl, newGuardRefp(falseVarp, VAccess::WRITE),
                                       new AstLogNot{fl, newGuardRefp(trueVarp)}});
        if (errorp) samplep = new AstIf{fl, newNoGuardErrorp(errorVarp), samplep};
        blockp->addStmtsp(samplep);
        const GuardResult result{newGuardRefp(trueVarp), newGuardRefp(falseVarp), errorp};
        recordGuardFlags(exprp, result, flags);
        return result;
    }
    AstNodeStmt* newGuardErrorSetp(AstNode* const nodep) {
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
        return new AstAssign{fl, newGuardRefp(m_guardItemp->errorVarp, VAccess::WRITE),
                             new AstConst{fl, AstConst::BitTrue{}}};
    }
    AstNodeStmt* newGuardErrorReturnp(AstNode* const nodep) {
        FileLine* const fl = nodep->fileline();
        AstNodeStmt* const reportp = newGuardErrorSetp(nodep);
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
            VL_RESTORER(m_inGuardPredicate);
            m_inGuardPredicate = true;
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
        return newReturnedTextp(fl, blockp);
    }
    // Format a bound reduction element of a guard, carrying receiver ERROR to its item.
    AstNodeExpr* formatGuardElementValue(AstNodeExpr* const exprp) {
        FileLine* const fl = exprp->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardElement"), nullptr, true};
        AstVar* const errorVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::BitFalse{}}});
        // Sampling can replace a root conditional; keep it owned until the walk is finished.
        AstBegin* const wrapperp = newGuardReadWrapperp(fl, exprp->cloneTree(false));
        const GuardRead read = editGuardReceivers(wrapperp->declsp(), blockp, errorVarp);
        AstNode* const sampledClonep = wrapperp->declsp()->unlinkFrBack();
        VL_DO_DANGLING(wrapperp->deleteTree(), wrapperp);
        VL_DO_DANGLING(sampledClonep->deleteTree(), sampledClonep);
        // Keep symbolic receiver paths intact for solver registration and member naming.
        if (!read.sampled) {
            VL_DO_DANGLING(blockp->deleteTree(), blockp);
            return VN_AS(iterateSubtreeReturnEdits(exprp), NodeExpr);
        }
        if (read.checked) {
            blockp->addStmtsp(
                new AstIf{fl, newGuardRefp(errorVarp), newGuardErrorReturnp(blockp)});
        }
        blockp->addStmtsp(new AstCReturn{fl, VN_AS(iterateSubtreeReturnEdits(exprp), NodeExpr)});
        return newReturnedTextp(fl, blockp);
    }
    // Validate a complete STATE subtree before it becomes a residual guard constant.
    AstNodeExpr* formatStateGuardValue(AstNodeExpr* const exprp) {
        // Leaves cannot dereference a receiver or contain a reduction callback.
        if (VN_IS(exprp, Const) || VN_IS(exprp, VarRef) || VN_IS(exprp, LambdaArgRef)) {
            return getConstFormat(exprp);
        }
        FileLine* const fl = exprp->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardNative"), nullptr, true};
        AstVar* const errorVarp = newGuardVarp(fl, blockp, blockp->findBitDType());
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(errorVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::BitFalse{}}});
        AstBegin* const wrapperp = newGuardReadWrapperp(fl, exprp->cloneTree(false));
        const GuardRead read
            = editGuardReceivers(wrapperp->declsp(), blockp, errorVarp, false, true);
        AstNodeExpr* const valuep = VN_AS(wrapperp->declsp()->unlinkFrBack(), NodeExpr);
        VL_DO_DANGLING(wrapperp->deleteTree(), wrapperp);
        if (!read.sampled) {
            VL_DO_DANGLING(valuep->deleteTree(), valuep);
            VL_DO_DANGLING(blockp->deleteTree(), blockp);
            return getConstFormat(exprp);
        }
        // The current visitor may still own exprp; edit only its fresh clone.
        VL_DO_DANGLING(pushDeletep(exprp), exprp);
        AstVar* const valueVarp = newGuardVarp(fl, blockp, valuep->dtypep());
        blockp->addStmtsp(new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE),
                                        new AstConst{fl, AstConst::DTyped{}, valuep->dtypep()}});
        blockp->addStmtsp(
            new AstIf{fl, newNoGuardErrorp(errorVarp),
                      new AstAssign{fl, newGuardRefp(valueVarp, VAccess::WRITE), valuep}});
        if (read.checked) {
            blockp->addStmtsp(new AstIf{fl, newGuardRefp(errorVarp), newGuardErrorSetp(blockp)});
        }
        return getConstFormat(new AstExprStmt{fl, blockp, newGuardRefp(valueVarp)});
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
        relinker.relink(newReturnedTextp(fl, blockp));
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
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VvalueConditional"),
                           new AstIf{fl, nodep->condp()->unlinkFrBack(),
                                     new AstCReturn{fl, nodep->thenp()->unlinkFrBack()},
                                     new AstCReturn{fl, nodep->elsep()->unlinkFrBack()}},
                           true};
        nodep->replaceWith(newReturnedTextp(fl, blockp));
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
        const bool elemMemberRef = VN_IS(nodep->backp(), MemberRef);
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
            && (keyIsString || keyIsPackedString || keyIsIntegral) && !elemMemberRef) {
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
        const bool objectElem
            = VN_IS(RandomizeUtil::arrayElementDTypep(nodep->dtypep()), ClassRefDType);
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
        } else if (const AstMemberRef* const memberRefp = VN_CAST(atp->fromp(), MemberRef)) {
            varp = memberRefp->varp();
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
    void visit(AstMemberRef* nodep) override {
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
            while (const AstMemberRef* const memberRefp = VN_CAST(rootNodep, MemberRef)) {
                rootNodep = memberRefp->fromp();
            }

            // Element select at the root, and the array it selects from. A field of the object
            // of a dynamic array element (ARRAY_AT) is handled below, unless deeper in it.
            AstNodeExpr* arraySelp = nullptr;
            AstNodeExpr* selArrayp = nullptr;
            if (AstNodeSel* const nodeSelp = VN_CAST(rootNodep, ArraySel)) {
                arraySelp = nodeSelp;
                selArrayp = nodeSelp->fromp();
            } else if (AstNodeSel* const assocSelp = VN_CAST(rootNodep, AssocSel)) {
                arraySelp = assocSelp;
                selArrayp = assocSelp->fromp();
            } else if (AstCMethodHard* const atp = VN_CAST(rootNodep, CMethodHard)) {
                if (atp->method() == VCMethod::ARRAY_AT && nodep->fromp() != rootNodep) {
                    arraySelp = atp;
                    selArrayp = atp->fromp();
                }
            }

            if (arraySelp) {
                AstNodeDType* const arrayDtp = selArrayp->dtypep()->skipRefp();
                AstNodeDType* const elemDtp
                    = arrayDtp->subDTypep() ? arrayDtp->subDTypep()->skipRefp() : nullptr;
                if (elemDtp && VN_IS(elemDtp, ClassRefDType)) {
                    const bool isSimple = nodep->fromp() == rootNodep && VN_IS(selArrayp, VarRef);
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
                        = isSimple ? newHandlesActivep(m_memberMap, selArrayp, true, false)
                                   : nullptr;
                    const bool stateField = isStateElemField(nodep);  // Before formatting
                    iterateChildren(nodep);
                    AstSFormatF* const newp = new AstSFormatF{fl, "%s." + nodep->name(), false,
                                                              nodep->fromp()->unlinkFrBack()};
                    if (stateField) addElemName(nodep, newp);
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
                    // Global constraint - unwrap the MemberRef
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
        // Handle MemberRef references created by captureRefByThis()
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
                const bool stateField = isStateElemField(nodep);  // Before formatting
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
                    if (stateField) addElemName(nodep, newp);
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
    void hoistGuardedSoftItems(AstNode*& lastp, AstNodeConstraintItem* itemsp,
                               AstNodeExpr* condp) {
        for (AstNodeConstraintItem* const itemp : VNList<AstNodeConstraintItem>{itemsp}) {
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
            AstNodeConstraintItem* hoistp;
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
        UASSERT_OBJ(!foldOwner || (m_constraintVars.empty() && m_foldElemNames.namesp.empty()),
                    nodep, "Constraint names of an earlier fold were not taken over");
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
    void visit(AstConstraintForeach* nodep) override {
        // Convert to plain foreach
        FileLine* const fl = nodep->fileline();
        // Registrations referencing the index are appended to the holder of the body
        VL_RESTORER(m_foreachBodyp);
        VL_RESTORER_COPY(m_foreachIdxVars);
        for (AstNode* const elemp : nodep->headerp()->elementspList()) {
            if (const AstVar* const varp = VN_CAST(elemp, Var)) m_foreachIdxVars.insert(varp);
        }

        if (!nodep->bodyp()) {
            nodep->unlinkFrBack();
        } else if (m_wantSingle) {
            // editSingle moves the items out to the fold, leaving the registrations
            AstBegin* const regsHolderp = SmtUtil::newItemsHolderp(fl, nullptr);
            m_foreachBodyp = regsHolderp;
            AstNodeExpr* const itemp = editSingle(fl, nodep->bodyp());
            if (!itemp) {  // All items were ignored with a warning
                VL_DO_DANGLING(regsHolderp->deleteTree(), regsHolderp);
                VL_DO_DANGLING(nodep->unlinkFrBack()->deleteTree(), nodep);
                return;
            }
            AstVar* const textVarp = newTextVarp(nodep);
            AstNodeStmt* bodyp = prependDistPreamble(nodep, newTermAppendp(fl, textVarp, itemp));
            if (AstNode* const regsp = regsHolderp->declsp()) {
                bodyp = AstNode::addNext(VN_AS(regsp->unlinkFrBackWithNext(), NodeStmt), bodyp);
            }
            VL_DO_DANGLING(regsHolderp->deleteTree(), regsHolderp);
            nodep->replaceWith(newTextBuildp(
                fl, textVarp, "", new AstForeach{fl, nodep->headerp()->unlinkFrBack(), bodyp},
                newTextApplyp(fl, textVarp, "bvand", "#b1")));
        } else {
            AstBegin* const holderp
                = SmtUtil::newItemsHolderp(fl, nodep->bodyp()->unlinkFrBackWithNext());
            m_foreachBodyp = holderp;
            AstNodeStmt* const bodyp = prependDistPreamble(nodep, holderp);
            AstBegin* const blockp
                = new AstBegin{fl, m_uniqueNames.get("__VrandBlock"),
                               new AstForeach{fl, nodep->headerp()->unlinkFrBack(), bodyp}, true};
            nodep->replaceWith(blockp);
            iterateAndNextNull(holderp->declsp());
            if (!holderp->declsp()) {  // All items were ignored with a warning
                VL_DO_DANGLING(pushDeletep(blockp->unlinkFrBack()), blockp);
            } else {
                SmtUtil::replaceWithLowered(holderp);
            }
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

        for (AstNodeExpr* const lhsp : nodep->lhsspList()) {
            for (AstNodeExpr* const rhsp : nodep->rhsspList()) {
                AstCMethodHard* const callp = new AstCMethodHard{
                    fl, new AstVarRef{fl, genModp, m_genp, VAccess::READWRITE},
                    VCMethod::RANDOMIZER_SOLVE_BEFORE};
                callp->dtypeSetVoid();
                addSolveBeforePins(callp, lhsp);
                addSolveBeforePins(callp, rhsp);
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
            genVarp = SmtUtil::getRandomGenerator(m_classp);
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
        AstNodeStmt* setupStmtsp = nullptr;
        // Under a condition the distinctness must instead become part of the guarded
        // constraint expression, which needs an element count known at verilation time
        std::vector<std::string> smtExprs;
        for (AstNode* const itemp : nodep->rangespList()) {
            // An array of the class, or of a member object reached through member selects
            AstMemberRef* memberRefp = VN_CAST(itemp, MemberRef);
            // A variable of the class itself, captured as this.x in a randomize() with
            if (memberRefp && isCapturedThisSel(memberRefp)) memberRefp = nullptr;
            const AstNode* rootp = itemp;
            while (const AstMemberRef* const selp = VN_CAST(rootp, MemberRef)) {
                rootp = selp->fromp();
            }
            if (VN_IS(rootp, VarRef)) {
                AstVar* const varp = VN_IS(itemp, MemberRef) ? VN_AS(itemp, MemberRef)->varp()
                                                             : VN_AS(itemp, VarRef)->varp();
                const std::string smtName
                    = memberRefp ? buildMemberPath(memberRefp) : varp->name();
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
                if (memberRefp) {
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
                if (!memberRefp && varp->user4p() && m_sizeConstrainedArraysp) {
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

    AstNodeStmt* wrapGuardItemCall(AstCMethodHard* const callp, AstNodeStmt* const stmtp,
                                   AstVar* const errorVarp) {
        FileLine* const fl = callp->fileline();
        AstBegin* const blockp
            = new AstBegin{fl, m_uniqueNames.get("__VguardItem"), nullptr, true};
        blockp->addDeclsp(errorVarp);
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
        if (wasSoft) {
            // A soft's list is what disable soft removes it by, not solver dependencies
            AstNode* const oldNamesp = failp->pinsp()->nextp();
            oldNamesp->replaceWith(new AstCExpr{fl, AstCExpr::Pure{}, "{}"});
            VL_DO_DANGLING(pushDeletep(oldNamesp), oldNamesp);
        }
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
        // Solver variables directly in a soft payload, which 'disable soft' removes it by
        // (IEEE 1800-2023 18.5.13.2). Not those of a guard folded around it.
        std::set<std::string> softVars;
        ElemNames elemNames;  // Like vars
        ElemNames softElemNames;  // Like softVars
        const bool foldTaker = nodep == m_foldTakerp;
        if (!m_wantSingle) {
            if (foldTaker) {
                vars.swap(m_constraintVars);
                std::swap(elemNames, m_foldElemNames);
                // A soft fold has only its payload's names so far; its guard is formatted
                // below
                if (nodep->isSoft()) {
                    softVars = vars;
                    std::swap(softElemNames, elemNames);
                }
                item.errorVarp = m_foldErrorVarp;
                m_foldErrorVarp = nullptr;
                m_foldTakerp = nullptr;
            }
            UASSERT_OBJ(m_constraintVars.empty() && m_foldElemNames.namesp.empty(), nodep,
                        "Constraint names carried over from another constraint");
        }
        VL_RESTORER(m_constraintVarsp);
        m_constraintVarsp = m_wantSingle ? &m_constraintVars : &vars;
        VL_RESTORER(m_elemNamesp);
        m_elemNamesp = m_wantSingle ? &m_foldElemNames : &elemNames;
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
        // Before any size gate is added around the payload
        if (!foldTaker && nodep->isSoft()) {
            softVars = vars;
            std::swap(softElemNames, elemNames);
        }
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
        // The variable list is always pin 2 (EmitCFunc locates the filename after it): a hard
        // constraint's solver dependencies, or the solver variables a soft payload names, which
        // disable soft removes it by (IEEE 1800-2023 18.5.13.2)
        callp->addPinsp(
            nodep->isSoft()
                ? newSoftVarsListp(nodep->fileline(), softVars, softElemNames)
                : new AstCExpr{nodep->fileline(), AstCExpr::Pure{}, constraintVarsList(vars)});
        elemNames.clear();
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
        AstNodeStmt* stmtp = callp->makeStmt();
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
                        && VN_AS(basep->backp(), MemberRef)->varp()->isRand()) {
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

            AstVar* const textVarp = newTextVarp(nodep);
            AstStmtExpr* const appendp
                = newTermAppendp(fl, textVarp, VN_AS(iterateSubtreeReturnEdits(itemp), NodeExpr));
            nodep->replaceWith(newTextBuildp(fl, textVarp, "",
                                             new AstForeach{fl, headerp, appendp},
                                             newTextApplyp(fl, textVarp, "bvor", "#b0")));
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

            // Keep nested indices distinct when compared before scoping in constifyEdit.
            AstVar* const loopVarp = new AstVar{
                fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__Vreduce"), nodep->findIntDType()};
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
            AstVar* const textVarp = newTextVarp(nodep);
            AstNodeStmt* bodyp;
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

                // Apply the operator to the text so far and the element's term
                AstNodeExpr* const openp = new AstConcatN{
                    fl, new AstConst{fl, AstConst::String{}, "(" + std::string{smtOp} + " "},
                    new AstVarRef{fl, textVarp, VAccess::READ}};
                bodyp = new AstAssign{
                    fl, new AstVarRef{fl, textVarp, VAccess::WRITE},
                    new AstConcatN{fl, openp, new AstConst{fl, AstConst::String{}, " "}}};
                AstNodeExpr* const elementTextp
                    = m_inGuardPredicate
                          ? formatGuardElementValue(VN_AS(perElemExprp, NodeExpr))
                          : VN_AS(iterateSubtreeReturnEdits(perElemExprp), NodeExpr);
                bodyp->addNext(newTextAppendp(fl, textVarp, elementTextp));
                bodyp->addNext(
                    newTextAppendp(fl, textVarp, new AstConst{fl, AstConst::String{}, ")"}));
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

                bodyp = newTermAppendp(fl, textVarp, varNamep);
            }

            // Build final expression
            AstForeach* const foreachp = new AstForeach{fl, headerp, bodyp};
            if (perElem) {
                // Per element: the nested operator terms, built from the identity
                nodep->replaceWith(newTextBuildp(fl, textVarp, identity, foreachp,
                                                 new AstVarRef{fl, textVarp, VAccess::READ}));
            } else {
                // Whole array variable: the operator applied to the element terms
                nodep->replaceWith(newTextBuildp(fl, textVarp, "", foreachp,
                                                 newTextApplyp(fl, textVarp, smtOp, identity)));
            }
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
            return;
        }

        // We've handled DYN_SIZE already if they should be randomized
        if (nodep->method() == VCMethod::DYN_SIZE || nodep->method() == VCMethod::ASSOC_SIZE) {
            AstNodeExpr* nodeExprp = nodep->fromp();
            // Check if it is a pure chain of MemberRef ended with VarRef
            // if not throw warning
            while (VN_IS(nodeExprp, MemberRef)) {
                nodeExprp = VN_AS(nodeExprp, MemberRef)->fromp();
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
            = V3Task::taskConnects(nodep, funcp->declsp(), nullptr, false);

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
    // Statements among the items need no lowering: the hoisted conditional disable-softs, the
    // registrations of a foreach body, and those that earlier items were lowered to
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
    AstNodeStmt* buildDisableSoftCallStmt(AstConstraintExpr* nodep) {
        FileLine* const fl = nodep->fileline();
        AstNodeExpr* keyp = nullptr;
        if (const AstNodeVarRef* const vrefp = VN_CAST(nodep->exprp(), NodeVarRef)) {
            keyp = new AstConst{fl, AstConst::String{}, vrefp->name()};
        } else if (const AstMemberRef* const mselp = VN_CAST(nodep->exprp(), MemberRef)) {
            // The name of its registration and of the soft constraints it appears in
            std::string fmt;
            AstNodeExpr* argsp = nullptr;
            bool randIndex = false;
            if (const AstNodeExpr* const callp = findSelCallp(mselp, randIndex)) {
                callp->v3error("'disable soft' of "
                               << mselp->prettyNameQ()
                               << " selects from the result of a call, but its"
                                  " operand must be a constraint primary"
                                  " (IEEE 1800-2023 18.5.13.2, A.1.10)");
                keyp = new AstConst{fl, AstConst::String{}, ""};  // Not run: compiling stops
            } else if (randIndex) {
                // The soft constraints are removed at setup, before the solver picks the
                // object, so its field has no name yet
                mselp->v3warn(E_UNSUPPORTED, "Unsupported: 'disable soft' of "
                                                 << mselp->prettyNameQ()
                                                 << " of an object selected by a random index");
                keyp = new AstConst{fl, AstConst::String{}, ""};  // Not run: compiling stops
            } else if (addSolverPathFormat(mselp, fmt, argsp)) {
                keyp = argsp ? static_cast<AstNodeExpr*>(new AstSFormatF{fl, fmt, false, argsp})
                             : new AstConst{fl, AstConst::String{}, fmt};
            } else {
                // Nothing was formatted below the part not named
                UASSERT_OBJ(!argsp, mselp, "Indices formatted for an unnamed object");
                mselp->v3warn(E_UNSUPPORTED, "Unsupported: 'disable soft' of "
                                                 << mselp->prettyNameQ()
                                                 << " of an object not selected only by"
                                                    " members and array elements");
                keyp = new AstConst{fl, AstConst::String{}, ""};  // Not run: compiling stops
            }
        } else {
            nodep->v3fatalSrc("Unexpected expression type in disable soft");
        }
        AstCMethodHard* const callp = new AstCMethodHard{
            fl, new AstVarRef{fl, VN_AS(m_genp->user2p(), NodeModule), m_genp, VAccess::READWRITE},
            VCMethod::RANDOMIZER_DISABLE_SOFT, keyp};
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
        for (AstNode* const stmtp : VNList<AstNode>{itemsp}) {
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
                                   AstNodeFTask* memberrefInitTaskp = nullptr,
                                   VInsertionSet<AstVar*>* sizeConstrainedArraysp = nullptr,
                                   AstNodeFTask* prepareConstrainedArraysp = nullptr,
                                   std::set<const AstVar*>* newWrittenVarsp = nullptr)
        : m_classp{classp}
        , m_inlineInitBlockp{inlineInitp}
        , m_memberrefInitTaskp{memberrefInitTaskp}
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
        // visitor skips these via visit(AstNodeStmt) above.
        if (AstNode* const hoistListp
            = nodep ? extractConditionalDisableSofts(nodep, nullptr) : nullptr) {
            nodep->addNext(hoistListp);
        }
        iterateAndNextNull(nodep);
    }
    // Constraint items calling functions with random arguments
    const std::vector<ConstraintFuncCall>& funcCalls() const { return m_funcCalls; }
};

//######################################################################
// SMT-LIB solver back-end

class SolverSmtLowering final : public V3SolverLowering {
    // STATE
    int m_distNum = 0;  // Dist bucket variable counter within a class for var naming
    std::set<std::string> m_writtenVars;  // Track write_var calls per class to avoid duplicates
    // m_writtenVars of each class, with those of its base classes
    std::map<const AstClass*, std::set<std::string>> m_classWrittenVars;
    // Classes whose randomization may randomize a randc variable
    std::unordered_set<const AstClass*> m_randcClasses;
    std::map<AstClass*, VInsertionSet<AstVar*>> m_sizeConstrainedArrays;  // Per-class arrays
    std::map<const AstVar*, AstVar*> m_memberSizeVars;  // Size variables of member arrays
    // Arrays of member objects, by SMT name, each with its member select
    using MemberArrays = std::map<std::string, const AstMemberRef*>;
    uint32_t m_uniqueConstraintId = 0;  // current ID of unique call
    std::map<AstClass*, std::vector<AstClass*>> m_derivedClasses;  // Directly derived classes
    std::map<const AstConstraint*, std::vector<ConstraintFuncCall>>
        m_constraintFuncCalls;  // Items of each constraint calling functions with random args
    std::set<const AstVar*> m_newWrittenVars;  // Variables registered in new() of their class
    std::unordered_set<const AstClass*> m_elemModePinPath;  // Classes newClassElemModePinsp is in
    V3UniqueNames m_randArrayUniqueNames{"__Vrandarr"};  // Array element loop indices
    // SMT names of the arrays each constraint sizes
    std::map<const AstConstraint*, std::set<std::string>> m_constraintSizedArrays;
    // How lowerClassRandomize solved a class
    struct ClassSolve final {
        bool sizePhase = false;  // Sizes are solved and arrays resized before the final solve
        AstNodeStmt* roundsFirstp = nullptr;  // First statement of the solve, if any
        AstVar* genp = nullptr;  // Randomizer of the class
    };
    std::map<const AstClass*, ClassSolve> m_classSolves;  // Per class
    // The solve lowerStdRandomizeWith added, for finishStdRandomizeWith
    struct StdFuncRounds final {
        AstNodeStmt* firstp = nullptr;  // First statement of the solve
        std::vector<ConstraintFuncCall> calls;  // Items calling functions with random args
    };
    std::map<const AstFunc*, StdFuncRounds> m_stdFuncRounds;  // Per std::randomize() function
    // Calls in the constraints of derived classes, from prepareInlineRandomize
    std::map<const AstClass*, std::vector<ConstraintFuncCall>> m_inlineDerivedCalls;

    // METHODS
    AstVar* getStaticRandModeVar(AstClass* const classp) {
        return m_modeVars.staticRandModeVarp(classp);
    }
    AstVar* getStaticConstraintModeVar(AstClass* const classp) {
        return m_modeVars.staticConstraintModeVarp(classp);
    }
    static AstVar* getConstraintModeVar(AstClass* const classp) {
        return RandModeVars::constraintModeVarp(classp);
    }

    // Expand unique{a,b,c} with explicit elements into pairwise != constraints.
    // Whole-array unique{arr} is left for ConstraintExprVisitor's rand_unique handling.
    // Recurses into conditional and foreach bodies, so that the pairwise
    // constraints stay under the guard they were written under.
    static void expandUniqueElementList(AstNode* itemsp) {
        for (AstNode* const itemp : VNList<AstNode>{itemsp}) {
            if (const AstConstraintIf* const ifp = VN_CAST(itemp, ConstraintIf)) {
                expandUniqueElementList(ifp->thensp());
                expandUniqueElementList(ifp->elsesp());
                continue;
            }
            if (const AstConstraintForeach* const foreachp = VN_CAST(itemp, ConstraintForeach)) {
                expandUniqueElementList(foreachp->bodyp());
                continue;
            }
            AstConstraintUnique* const uniquep = VN_CAST(itemp, ConstraintUnique);
            if (!uniquep) continue;

            std::vector<AstNodeExpr*> exprItems;
            bool hasArrayVarRef = false;
            for (AstNodeExpr* const rp : uniquep->rangespList()) {
                // A container's elements are made distinct by rand_unique, not pairwise
                const AstNodeDType* const dtypep = rp->dtypep()->skipRefp();
                if (VN_IS(dtypep, NodeArrayDType) || VN_IS(dtypep, QueueDType)
                    || VN_IS(dtypep, DynArrayDType) || VN_IS(dtypep, AssocArrayDType)
                    || VN_IS(dtypep, WildcardArrayDType)) {
                    hasArrayVarRef = true;
                    continue;
                }
                exprItems.push_back(rp);
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
    AstTask* createPrepareConstrainedArraysTask(AstClass* const classp) {
        static const char* const name = "__Vprepare_constrained_arrays";
        AstTask* const taskp = new AstTask{classp->fileline(), name};
        taskp->classMethod(true);
        classp->addMembersp(taskp);
        m_memberMap.insert(classp, taskp);
        return taskp;
    }
    AstTask* getCreateAggrResizeTask(AstClass* const classp) {
        static constexpr const char* const name = "__Vresize_constrained_arrays";
        AstTask* resizeTaskp = VN_AS(m_memberMap.findMember(classp, name), Task);
        if (resizeTaskp) return resizeTaskp;
        resizeTaskp = new AstTask{classp->fileline(), name};
        resizeTaskp->classMethod(true);
        resizeTaskp->isVirtual(true);
        classp->addMembersp(resizeTaskp);
        m_memberMap.insert(classp, resizeTaskp);
        return resizeTaskp;
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
    // Element at offset offsetp of array arrVarp of objp, or of 'this' if objp is nullptr
    static AstNodeExpr* newElemp(FileLine* const fl, AstNodeExpr* const objp,
                                 AstVar* const arrVarp, AstNodeExpr* const offsetp) {
        AstNodeExpr* const arrp = RandomizeUtil::newMemberRefp(fl, objp, arrVarp);
        AstNodeExpr* const elemp
            = VN_IS(arrVarp->dtypep()->skipRefp(), UnpackArrayDType)
                  ? static_cast<AstNodeExpr*>(new AstArraySel{fl, arrp, offsetp})
                  : new AstCMethodHard{fl, arrp, VCMethod::ARRAY_AT, offsetp};
        elemp->dtypep(arrVarp->dtypep()->skipRefp()->subDTypep());
        return elemp;
    }
    // Skip the elements without a randomized object in a constraint cloned for an array
    void skipInactiveElems(AstConstraint* const constrp, AstBegin* const holderp) {
        // A null element has no object (IEEE 1800-2023 18.4), and the object of an element
        // with rand_mode off is not randomized (18.8), so their constraints do not apply. Such a
        // clone is a foreach over the array, already lowered to setup statements in holderp,
        // which are skipped for those elements.
        const auto it = m_cloneObjps.find(constrp);
        if (it == m_cloneObjps.end()) return;
        AstMemberRef* const selp = VN_CAST(it->second.objp, MemberRef);
        AstVar* const arrVarp = selp ? selp->varp() : VN_AS(it->second.objp, VarRef)->varp();
        if (VN_IS(arrVarp->dtypep()->skipRefp(), ClassRefDType)) return;  // Cloned for an object
        AstNodeExpr* const objp = selp ? selp->fromp() : nullptr;
        AstForeach* const foreachp = VN_AS(VN_AS(holderp->declsp(), Begin)->stmtsp(), Foreach);
        FileLine* const fl = foreachp->fileline();
        std::vector<AstVar*> idxVarps;
        for (AstNode* nodep = foreachp->headerp()->elementsp(); nodep; nodep = nodep->nextp()) {
            idxVarps.push_back(VN_AS(nodep, Var));
        }
        AstNodeExpr* const elemp = RandomizeUtil::newElemSelp(
            fl, RandomizeUtil::newMemberRefp(fl, objp, arrVarp), idxVarps);
        AstNodeExpr* condp
            = new AstNeq{fl, elemp->cloneTree(false), new AstConst{fl, AstConst::Null{}}};
        if (AstVar* const modeVarp = m_elemModes.modeVarp(arrVarp)) {
            // Only the elements of a one-dimensional array have their own rand_mode()
            AstNodeExpr* const offsetp = RandomizeUtil::newElemOffsetp(
                fl, arrVarp->dtypep(), new AstVarRef{fl, idxVarps[0], VAccess::READ});
            condp = new AstLogAnd{
                fl, condp,
                new AstNot{fl, RandomizeUtil::newElemModeOffp(
                                   RandomizeUtil::newMemberRefp(fl, objp, modeVarp), offsetp)}};
            VL_DO_DANGLING(offsetp->deleteTree(), offsetp);
        }
        if (AstNodeExpr* const modep = newObjConstraintModep(elemp, it->second.origp)) {
            condp = new AstLogAnd{fl, condp, modep};
        }
        VL_DO_DANGLING(elemp->deleteTree(), elemp);
        AstNodeStmt* const bodyp = foreachp->bodyp()->unlinkFrBackWithNext();
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
        AstNodeExpr* const offsetp = RandomizeUtil::newElemOffsetp(
            fl, arrVarp->dtypep(), new AstVarRef{fl, idxVarp, VAccess::READ});
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
                                   new AstMemberRef{fl, elemp->cloneTree(false), memberVarp}));
            });
            pinsp
                = new AstIf{fl, new AstNeq{fl, elemp, new AstConst{fl, AstConst::Null{}}}, pinsp};
        } else {
            pinsp = newPinp(name, "(select " + name + " #x%8x)", elemp);
        }
        AstIf* const ifp
            = new AstIf{fl,
                        RandomizeUtil::newElemModeOffp(
                            RandomizeUtil::newMemberRefp(fl, objp, modeVarp), offsetp),
                        pinsp};
        VL_DO_DANGLING(offsetp->deleteTree(), offsetp);
        // In a block, so the loop variable is moved out of an enclosing 'if'
        return new AstBegin{
            fl, m_uniqueNames.get("__VrandBlock"),
            new AstForeach{
                fl,
                new AstForeachHeader{fl, RandomizeUtil::newMemberRefp(fl, objp, arrVarp), idxVarp},
                ifp},
            false};
    }
    // Statements pinning the elements with rand_mode off in the arrays of classp
    AstNodeStmt* newClassElemModePinsp(AstClass* const classp, AstVar* const genp,
                                       AstNodeExpr* const objp = nullptr,
                                       const std::string& prefix = "") {
        // Also those of its rand objects, as their constraints may be solved together with
        // classp's (IEEE 1800-2023 18.5.9). objp reaches classp, nullptr for 'this', and
        // prefix is classp's solver variable name prefix.
        if (m_elemModes.empty()) return nullptr;
        AstNodeStmt* stmtsp = nullptr;
        m_elemModePinPath.insert(classp);  // Against cycles of rand objects
        classp->foreachMember([&](AstClass*, AstVar* const varp) {
            if (AstVar* const modeVarp = m_elemModes.modeVarp(varp)) {
                stmtsp = AstNode::addNextNull(
                    stmtsp, newElemModePinsp(varp, modeVarp, genp, objp, prefix));
            }
            if (!varp->isRand()) return;
            const AstClassRefDType* const classRefp
                = VN_CAST(varp->dtypep()->skipRefp(), ClassRefDType);
            if (!classRefp || m_elemModePinPath.count(classRefp->classp())) return;
            FileLine* const fl = varp->fileline();
            AstNodeExpr* const subObjp = RandomizeUtil::newMemberRefp(fl, objp, varp);
            if (AstNodeStmt* const subStmtsp = newClassElemModePinsp(
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
            modesp = new AstMemberRef{fl, objp->cloneTree(false), modeVarp};
        }
        AstCMethodHard* const atp
            = new AstCMethodHard{fl, modesp, VCMethod::ARRAY_AT, new AstConst{fl, mode.index}};
        atp->dtypeSetUInt32();
        return atp;
    }
    AstNodeStmt* wrapIfConstraintMode(AstClass* classp, AstConstraint* const constrp,
                                      AstNodeStmt* stmtp) {
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
        return RandModeVars::wrapIfMode(rmode, modeVarp, stmtp);
    }
    AstTask* newSetupConstraintTask(AstClass* const nodep, const std::string& name) {
        AstTask* const taskp = new AstTask{nodep->fileline(), name + "_setup_constraint"};
        taskp->classMethod(true);
        nodep->addMembersp(taskp);
        return taskp;
    }
    AstTask* newResizeConstrainedArrayTask(AstClass* const nodep, const std::string& name) {
        AstTask* const taskp = new AstTask{nodep->fileline(), name + "_resize_constrained_array"};
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
    AstVar* sizeVarOf(AstVar* const arrVarp, const AstMemberRef* const mselp) const {
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
            sizeNodeExprp = buildMemberRefExprp(derefFromp, sizeVarp);
        } else {
            sizeNodeExprp = new AstVarRef{fl, sizeVarp, VAccess::READ};
        }
        sizeNodeExprp->user1(true);
        AstGteS* const sizeGtep = new AstGteS{fl, sizeNodeExprp, new AstConst{fl, 0}};
        sizeGtep->user1(true);
        return new AstConstraintExpr{fl, sizeGtep};
    }
    // Returns MemberRef chain, with deepest VarRef being reference to deepestVarp
    AstNodeExpr* buildMemberRefExprp(AstNodeExpr* exprp, AstVar* deepestVarp) {
        UASSERT_OBJ(VN_IS(exprp, MemberRef) || VN_IS(exprp, VarRef), exprp,
                    "Should be MemberRef or VarRef");

        AstNodeExpr* resExprp = nullptr;
        if (const AstMemberRef* const memberRefp = VN_CAST(exprp, MemberRef)) {
            resExprp = buildMemberRefExprp(memberRefp->fromp(), nullptr);
            AstVar* varp = memberRefp->varp();
            if (deepestVarp) varp = deepestVarp;
            resExprp = new AstMemberRef{exprp->fileline(), resExprp, varp};
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
        for (AstNode* const stmtp : VNList<AstNode>{stmtsp}) {
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
        AstFunc* const updatep = new AstFunc{nodep->fileline(), "__VupdateRandVars"};
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

    // Rewrite a LogIf-of-Dist chain into nested AstConstraintIf. The outermost
    // AstLogIf shell is left for the caller's AstConstraintExpr to free; inner
    // shells are deleted here once their children are transplanted.
    AstConstraintIf* liftLogIfChainToConstraintIf(AstLogIf* logIfp) {
        FileLine* const fl = logIfp->fileline();
        AstNodeExpr* const condp = logIfp->lhsp()->unlinkFrBack();
        AstNodeExpr* const rhsp = logIfp->rhsp()->unlinkFrBack();
        AstNodeConstraintItem* thenBodyp;
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
    AstNodeExpr* newModeBitRead(AstVar* varp, const AstMemberRef* memberRefp, AstVar* randModeVarp,
                                FileLine* fl) {
        AstNodeExpr* arrayp = nullptr;
        if (varp->lifetime().isStatic()) {
            AstClass* const ownerp = VN_CAST(varp->user2p(), Class);
            UASSERT_OBJ(ownerp, varp, "usesMode static var without an owning class");
            AstVar* const smodep = getStaticRandModeVar(ownerp);
            UASSERT_OBJ(smodep, varp, "usesMode static var without a static rand-mode array");
            arrayp = new AstVarRef{fl, VN_AS(smodep->user2p(), NodeModule), smodep, VAccess::READ};
        } else if (memberRefp) {
            AstVar* const memberModep
                = RandModeVars::randModeVarp(VN_AS(varp->user2p(), NodeModule));
            UASSERT_OBJ(memberModep, varp, "usesMode member without a class rand-mode array");
            arrayp = new AstMemberRef{fl, memberRefp->fromp()->cloneTreePure(false), memberModep};
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
    AstNodeExpr* newVarGate(AstVar* varp, const AstMemberRef* memberRefp, bool ownerLevel,
                            AstVar* randModeVarp, FileLine* fl) {
        if (!isSolvedVar(varp)) return new AstConst{fl, AstConst::BitTrue{}, ownerLevel};
        const RandomizeMode rmode = {.asUQuad = varp->user1()};
        if (!rmode.usesMode) return new AstConst{fl, AstConst::BitTrue{}};
        return newModeBitRead(varp, memberRefp, randModeVarp, fl);
    }

    // Change bit of one variable access, ANDed level by level down the
    // member-select owner path.
    AstNodeExpr* newAccessGate(const AstNode* nodep, bool ownerLevel, AstVar* randModeVarp,
                               FileLine* fl) {
        if (const AstMemberRef* const memberRefp = VN_CAST(nodep, MemberRef)) {
            return newGateAnd(
                fl, newVarGate(memberRefp->varp(), memberRefp, ownerLevel, randModeVarp, fl),
                newAccessGate(memberRefp->fromp(), true, randModeVarp, fl));
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
        if (VN_IS(nodep, NodeVarRef) || VN_IS(nodep, MemberRef)) {
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
    AstNodeConstraintItem* gateFrozenDist(AstNodeConstraintItem* chainp, AstDist* distp,
                                          AstVar* randModeVarp) {
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
        // Evaluate the 64-bit offset once before wide expansion can duplicate operands.
        // A C cast is only to a basic C type; a wider result needs zero extension.
        if (distWidth > VL_QUADSIZE) {
            AstVar* const offsetVarp
                = new AstVar{fl, VVarType::BLOCKTEMP, m_uniqueNames.get("__Vdist_offset"),
                             distp->findUInt64DType()};
            offsetVarp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            AstBegin* const blockp
                = new AstBegin{fl, m_uniqueNames.get("__Vdist_offset_block"), nullptr, true};
            blockp->addDeclsp(offsetVarp);
            blockp->addStmtsp(
                new AstAssign{fl, new AstVarRef{fl, offsetVarp, VAccess::WRITE}, offsetp});
            offsetp = new AstExprStmt{
                fl, blockp,
                new AstExtend{fl, new AstVarRef{fl, offsetVarp, VAccess::READ}, distWidth}};
        } else {
            offsetp = new AstCCast{fl, offsetp, distWidth};
        }
        AstNodeExpr* const valuep = new AstAdd{fl, irp->lhsp()->cloneTreePure(false), offsetp};
        AstNodeExpr* const eqp = new AstEq{fl, distExprCopyp, valuep};
        eqp->user1(true);
        return eqp;
    }

    // Soft weighted bucket chain: select a bucket by bucketVar against cumulative weights.
    AstConstraintExpr* buildWeightedBucketChain(AstDist* distp,
                                                const std::vector<DistBucket>& buckets,
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
    void lowerDistConstraints(AstNodeFTask* taskp, AstNodeConstraintItem* constrItemsp,
                              AstVar* randModeVarp, AstConstraintForeach* foreachp = nullptr) {
        // When inside a foreach, bucket preamble stmts are stored in foreachp->user3p()
        // (as a linked list) so visit(AstConstraintForeach*) can inject them into the
        // real AstForeach body. Recursive branches share and append to the same list. The
        // variables are always declared in taskp, assigned before use in each iteration.
        auto addStmt = [&](AstNodeStmt* nodep) {
            if (foreachp) {
                foreachp->user3p(AstNode::addNext(foreachp->user3p(), nodep));
            } else {
                taskp->addStmtsp(nodep);
            }
        };

        for (AstNodeConstraintItem* const itemp : VNList<AstNodeConstraintItem>{constrItemsp}) {
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
            taskp->addDeclsp(totalVarp);
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
            taskp->addDeclsp(bucketVarp);

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

            AstNodeConstraintItem* chainp
                = buildWeightedBucketChain(distp, buckets, bucketVarp, cumSums);

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

    // Clone a list of constraint items with the dist preambles of their foreach items
    static AstNode* cloneWithDistPreambles(AstNode* const nodep) {
        // The preambles are off-tree, so are cloned separately. Their references to the loop
        // indices, also of enclosing loops, are moved to the indices of the cloned loops. The
        // dist variables they assign are declared in the function, shared by both.
        AstNode* const clonep = nodep->cloneTree(true);
        std::unordered_map<const AstVar*, AstVar*> idxVarps;  // Index var -> its clone
        // Each foreach with a preamble, and its clone
        std::vector<std::pair<AstConstraintForeach*, AstConstraintForeach*>> withPreambleps;
        nodep->foreachAndNext([&](AstConstraintForeach* const foreachp) {
            AstConstraintForeach* const clonedForeachp = foreachp->clonep();
            AstNode* clonedElemp = clonedForeachp->headerp()->elementsp();
            for (AstNode* const elemp : foreachp->headerp()->elementspList()) {
                if (AstVar* const varp = VN_CAST(elemp, Var)) {
                    idxVarps.emplace(varp, VN_AS(clonedElemp, Var));
                }
                clonedElemp = clonedElemp->nextp();
            }
            if (foreachp->user3p()) withPreambleps.emplace_back(foreachp, clonedForeachp);
        });
        for (const auto& pair : withPreambleps) {
            AstNode* const preamblep = pair.first->user3p()->cloneTree(true);
            preamblep->foreachAndNext([&](AstVarRef* const refp) {
                const auto it = idxVarps.find(refp->varp());
                if (it != idxVarps.end()) refp->varp(it->second);
            });
            pair.second->user3p(preamblep);
        }
        return clonep;
    }
    // Delete the off-tree dist preambles of the foreach items under nodep
    static void deleteDistPreambles(AstNode* const nodep) {
        nodep->foreach([](AstConstraintForeach* const foreachp) {
            if (AstNode* const preamblep = foreachp->user3p()) {
                foreachp->user3p(nullptr);
                VL_DO_DANGLING(preamblep->deleteTree(), preamblep);
            }
        });
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
                                       const AstMemberRef* const mselp, const VAccess access) {
        if (!mselp) return new AstVarRef{fl, VN_AS(varp->user2p(), NodeModule), varp, access};
        AstMemberRef* const selp
            = new AstMemberRef{fl, mselp->fromp()->cloneTreePure(false), varp};
        selp->access(access);
        selp->foreach([access](AstVarRef* const refp) { refp->access(access); });
        return selp;
    }
    // SMT name of varp in the object of member select mselp, or in this object without mselp
    static std::string siblingSmtName(const AstVar* const varp, const AstMemberRef* const mselp) {
        return mselp ? buildMemberPath(mselp->fromp()) + "." + varp->name() : varp->name();
    }
    // Statements stmtsp on the array of member select mselp, if any, run only while the
    // handles to its object are not null
    AstNodeStmt* newIfNonNullp(FileLine* const fl, AstNodeStmt* const stmtsp,
                               const AstMemberRef* const mselp) {
        // The object of a null handle is not randomized (IEEE 1800-2023 18.4), and its
        // constraints copied into this class are not solved
        if (!mselp) return stmtsp;
        return new AstIf{fl, newHandlesActivep(m_memberMap, mselp->fromp(), false, true), stmtsp};
    }
    // Add write_var calls for each array element after resizing it with array-size constraint
    void addArrayElemRefresh(FileLine* const fl, AstVar* const arrVarp, AstFunc* const randomizep,
                             AstVar* const genp, const AstMemberRef* const mselp = nullptr) {
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

        const size_t width = RandomizeUtil::arrayElementDTypep(arrVarp->dtypep())->width();

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
                                    const AstMemberRef* const mselp = nullptr) {
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
                                const AstMemberRef* const mselp = nullptr) const {
        AstVar* const sizeVarp = sizeVarOf(arrVarp, mselp);
        AstCMethodHard* const currentSizep = new AstCMethodHard{
            fl, newSiblingRefp(fl, arrVarp, mselp, VAccess::READ), VCMethod::DYN_SIZE};
        currentSizep->dtypep(sizeVarp->dtypep());
        return new AstAssign{fl, newSiblingRefp(fl, sizeVarp, mselp, VAccess::WRITE),
                             currentSizep};
    }
    void addFrozenSizePin(FileLine* const fl, AstVar* const arrVarp, AstFunc* const randomizep,
                          AstVar* const genp, AstVar* const randModeVarp,
                          const AstMemberRef* const mselp = nullptr) {
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
        AstNodeStmt* const stmtsp = newSizeVarAssign(fl, arrVarp, mselp);
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
                if (const AstMemberRef* const mselp = VN_CAST(resizep->fromp(), MemberRef)) {
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
            const AstMemberRef* const mselp = pathMsel.second;
            addFrozenSizePin(fl, mselp->varp(), randomizep, genp, randModeVarp, mselp);
        }
    }

    static void copyVariableRegistrations(AstFunc* const sourcep, AstFunc* const targetp) {
        for (AstNodeStmt* const stmtp : sourcep->stmtspList()) {
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
    std::vector<ConstraintFuncCall>
    derivedFuncCalls(AstClass* const classp, const std::function<void(AstClass*)>& lowerClass) {
        // The constraint setup is virtual, so 'randomize() with' through a base class handle
        // adds the constraints of the object's class
        std::vector<ConstraintFuncCall> calls;
        for (AstClass* const derivedp : m_derivedClasses[classp]) {
            if (derivedp->user1()) {
                // Lower its constraints first; that resets the per-class written variables
                VL_RESTORER_COPY(m_writtenVars);
                lowerClass(derivedp);
            }
            for (AstNode* itemp = derivedp->membersp(); itemp; itemp = itemp->nextp()) {
                if (const AstConstraint* const constrp = VN_CAST(itemp, Constraint)) {
                    const std::vector<ConstraintFuncCall>& constrCalls
                        = m_constraintFuncCalls[constrp];
                    calls.insert(calls.end(), constrCalls.begin(), constrCalls.end());
                }
            }
            const std::vector<ConstraintFuncCall> deeperCalls
                = derivedFuncCalls(derivedp, lowerClass);
            calls.insert(calls.end(), deeperCalls.begin(), deeperCalls.end());
        }
        return calls;
    }

    // Repeat the statements from firstp on in rounds that solve function arguments first
    static void addFuncRounds(AstFunc* const funcp, AstNodeStmt* const firstp, AstVar* const genp,
                              AstVar* const solveGenp, AstVar* const okVarp,
                              const AstFunc* const basicFuncp,
                              const std::vector<ConstraintFuncCall>& calls,
                              AstNodeStmt* const roundSetupp = nullptr) {
        const ConstraintFuncRounds rounds{calls};
        if (!rounds.lastRound()) {
            if (roundSetupp) VL_DO_DANGLING(roundSetupp->deleteTree(), roundSetupp);
            return;
        }
        FileLine* const fl = funcp->fileline();
        AstNodeModule* const genModp = VN_CAST(genp->user2p(), NodeModule);
        AstLoop* const loopp = new AstLoop{fl, roundSetupp};
        // Declarations are not statements, so stay outside of the loop
        if (firstp) loopp->addStmtsp(firstp->unlinkFrBackWithNext());
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
            funcp->addDeclsp(basicOkVarp);
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
        randomizep->addDeclsp(sizeOkVarp);
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
                              AstNodeStmt* const setupStmtsp) {
        FileLine* const fl = randomizep->fileline();
        for (AstVar* const arrVarp : sizeArrayVars) {
            addArrayElemRefresh(fl, arrVarp, randomizep, setupGenp);
        }
        // Member object arrays are registered when constraints use their elements
        for (const auto& pathMsel : memberArrays) {
            if (!writtenVars.count(pathMsel.first)) continue;
            const AstMemberRef* const mselp = pathMsel.second;
            addArrayElemRefresh(fl, mselp->varp(), randomizep, setupGenp, mselp);
        }
        randomizep->addStmtsp(implementConstraintsClear(fl, setupGenp));
        randomizep->addStmtsp(setupStmtsp);
        // The arrays are resized once, so their sizes must not change in the final solve
        for (AstVar* const arrVarp : resizedArrayVars) {
            randomizep->addStmtsp(newPinSizeVariable(fl, arrVarp, solveGenp));
        }
        for (const auto& pathMsel : memberArrays) {
            const AstMemberRef* const mselp = pathMsel.second;
            randomizep->addStmtsp(
                newIfNonNullp(fl, newPinSizeVariable(fl, mselp->varp(), solveGenp, mselp), mselp));
        }
    }

public:
    // CONSTRUCTORS
    SolverSmtLowering(VMemberMap& memberMap, V3UniqueNames& uniqueNames,
                      const RandModeVars& modeVars, ElemRandModes& elemModes,
                      const ClonedConstraints& cloneObjps, VNDeleter& deleter)
        : V3SolverLowering{memberMap, uniqueNames, modeVars, elemModes, cloneObjps, deleter} {
        findRandcClasses(v3Global.rootp());
        v3Global.rootp()->foreach([&](AstClass* const classp) {
            if (classp->extendsp())
                m_derivedClasses[classp->extendsp()->classp()].push_back(classp);
        });
    }
    ~SolverSmtLowering() override = default;

    // V3SolverLowering
    void prepareClass(AstClass* classp) override { createRandomGenerator(classp); }
    void startClass(AstClass*) override {
        m_writtenVars.clear();  // Each class has its own set of written variables
    }
    void lowerConstraintMethod(AstNodeModule* modp, AstConstraint* constrp,
                               AstCMethodHard* nodep) override {
        // Replace '.size()' of a constrained array with a solver size variable
        FileLine* const fl = nodep->fileline();
        // The size of an associative array is not random (IEEE 1800-2023 18.4), so it stays
        // a state value
        if (nodep->fromp()->user1() && nodep->method() == VCMethod::DYN_SIZE) {
            AstClass* const classp = VN_AS(modp, Class);
            // The array is a member of this class, or of a rand member object (global
            // constraints, IEEE 1800-2023 18.5.8) reached through a member select chain
            AstNodeExpr* const arrayp = nodep->fromp();
            AstMemberRef* const memberSelp = VN_CAST(arrayp, MemberRef);
            AstNodeExpr* rootp = arrayp;
            while (AstMemberRef* const selp = VN_CAST(rootp, MemberRef)) rootp = selp->fromp();
            // Warning from ConstraintExprVisitor will be thrown
            if (!VN_IS(rootp, VarRef)) return;
            AstVar* const queueVarp
                = memberSelp ? memberSelp->varp() : VN_AS(arrayp, VarRef)->varp();
            AstVar* const sizeVarp
                = memberSelp ? createOrGetMemberSizeVar(queueVarp, fl, nodep->findIntDType())
                             : createOrGetSizeVar(queueVarp, fl, nodep->findIntDType());
            const auto newSizeRefp = [&]() -> AstNodeExpr* {
                if (memberSelp) return buildMemberRefExprp(memberSelp, sizeVarp);
                return new AstVarRef{fl, VN_AS(sizeVarp->user2p(), NodeModule), sizeVarp,
                                     VAccess::READ};
            };
            // Each constraint sizing the array resizes it and guards its size, so
            // constraint_mode(0) leaves the array unchanged only when all are off
            if (m_constraintSizedArrays[constrp].insert(buildMemberPath(arrayp)).second) {
                AstTask* resizerTaskp = VN_AS(constrp->user3p(), Task);
                if (!resizerTaskp) {
                    resizerTaskp = newResizeConstrainedArrayTask(classp, constrp->name());
                    constrp->user3p(resizerTaskp);
                }
                AstCMethodHard* const resizep = new AstCMethodHard{
                    fl, arrayp->unlinkFrBack(), VCMethod::DYN_RESIZE, newSizeRefp()};
                resizep->dtypep(nodep->findVoidDType());
                resizerTaskp->addStmtsp(
                    newIfNonNullp(fl, new AstStmtExpr{fl, resizep}, memberSelp));

                // Since size variable is signed int, we need additional constraint
                // to make sure it is always >= 0.
                constrp->addItemsp(createSizeGteZeroConstraint(fl, sizeVarp, memberSelp));
            }
            AstNodeExpr* const sizeRefp = newSizeRefp();
            sizeRefp->user1(true);
            nodep->replaceWith(sizeRefp);
            VL_DO_DANGLING(nodep->deleteTree(), nodep);
        }
    }
    AstNodeExpr* lowerClassRandomize(AstClass* nodep, AstFunc* randomizep,
                                     AstVar* randModeVarp) override {
        m_distNum = 0;
        FileLine* const fl = nodep->fileline();
        AstVar* const fvarp = randomizep->fvarp();
        AstNodeExpr* beginValp = nullptr;
        bool sizePhase = false;  // Sizes are solved and arrays resized before the final solve
        AstNodeStmt* roundsFirstp = nullptr;  // First statement of the solve
        AstVar* genp = SmtUtil::getRandomGenerator(nodep);
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

                if (constrp->itemsp()) {
                    // Capture the original items under the same mode guard as the
                    // SMT setup. Inherited setup tasks retain their own metadata.
                    AstNodeStmt* const fastp
                        = FastConstraintBuilder::apply(constrp->itemsp(), genp);
                    taskp->addStmtsp(wrapIfConstraintMode(nodep, constrp, fastp));
                    expandUniqueElementList(constrp->itemsp());
                }
                if (constrp->itemsp()) {
                    lowerDistConstraints(taskp, constrp->itemsp(), randModeVarp);
                }
                VInsertionSet<AstVar*>& sizeArrays = m_sizeConstrainedArrays[classp];
                if (constrp->itemsp()) {
                    // Lowered in taskp, so its messages name the instance, then placed after
                    // the registrations it makes there
                    AstBegin* const holderp = SmtUtil::newItemsHolderp(
                        constrp->fileline(), constrp->itemsp()->unlinkFrBackWithNext());
                    taskp->addStmtsp(holderp);
                    const ConstraintExprVisitor exprVisitor{classp,
                                                            m_memberMap,
                                                            holderp->declsp(),
                                                            nullptr,
                                                            genp,
                                                            randModeVarp,
                                                            m_writtenVars,
                                                            &m_uniqueConstraintId,
                                                            m_uniqueNames,
                                                            taskp,
                                                            &sizeArrays,
                                                            prepareArraysTaskp,
                                                            &m_newWrittenVars};
                    std::vector<ConstraintFuncCall>& calls = m_constraintFuncCalls[constrp];
                    const std::vector<ConstraintFuncCall>& newCalls = exprVisitor.funcCalls();
                    calls.insert(calls.end(), newCalls.begin(), newCalls.end());
                    holderp->unlinkFrBack();
                    if (!holderp->declsp()) {
                        VL_DO_DANGLING(holderp->deleteTree(), holderp);
                        return;
                    }
                    skipInactiveElems(constrp, holderp);
                    AstNodeStmt* stmtsp = wrapIfConstraintMode(nodep, constrp, holderp);
                    // The constraints of objects of inactive handles are not solved
                    const auto it = m_cloneObjps.find(constrp);
                    if (it != m_cloneObjps.end()) {
                        if (AstNodeExpr* const activep
                            = newHandlesActivep(m_memberMap, it->second.objp, true, true)) {
                            stmtsp = new AstIf{constrp->fileline(), activep, stmtsp};
                        }
                    }
                    taskp->addStmtsp(stmtsp);
                    SmtUtil::replaceWithLowered(holderp);
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
                AstTask* const setupAllTaskp
                    = SmtUtil::getCreateConstraintSetupFunc(nodep, m_memberMap);
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
                if (AstNodeStmt* const pinsp = newClassElemModePinsp(nodep, genp)) {
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
            AstTask* const setupAllTaskp
                = SmtUtil::getCreateConstraintSetupFunc(nodep, m_memberMap);
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
                randomizep->addDeclsp(finalOkVarp);
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
        m_classSolves[nodep] = ClassSolve{sizePhase, roundsFirstp, genp};
        return beginValp;
    }
    bool basicInClassSolve(AstClass* nodep) override { return m_classSolves[nodep].sizePhase; }
    void finishClassRandomize(AstClass* nodep, AstFunc* randomizep,
                              const AstFunc* basicRandomizep) override {
        const ClassSolve& solve = m_classSolves[nodep];
        if (!solve.roundsFirstp) return;
        addFuncRounds(randomizep, solve.roundsFirstp, solve.genp, solve.genp, randomizep->fvarp(),
                      basicRandomizep, classFuncCalls(nodep));
    }
    void addAfterClassSolve(AstClass* nodep, AstFunc* randomizep) override {
        const auto sizeArraysIt = m_sizeConstrainedArrays.find(nodep);
        const bool needsSizePhase
            = sizeArraysIt != m_sizeConstrainedArrays.end() && !sizeArraysIt->second.empty();
        // Size-only resize fallback (no element constraint, so no two-pass phase).
        // Must run after the solver .next() that sets the size variable.
        if (needsSizePhase) return;
        if (AstTask* const resizeAllTaskp
            = VN_AS(m_memberMap.findMember(nodep, "__Vresize_constrained_arrays"), Task)) {
            AstTaskRef* const resizeTaskRefp = new AstTaskRef{nodep->fileline(), resizeAllTaskp};
            randomizep->addStmtsp(resizeTaskRefp->makeStmt());
        }
    }
    void lowerInlineRandomize(AstNodeFTaskRef* nodep, AstClass* classp, AstFunc* randomizeFuncp,
                              AstNode* capturedTreep, const AstVar* thisVarp,
                              AstNodeExpr* basicRandomizeFuncCallp) override {
        AstVar* const classGenp = SmtUtil::getRandomGenerator(classp);
        std::vector<ConstraintFuncCall> calls = std::move(m_inlineDerivedCalls[classp]);
        m_inlineDerivedCalls.erase(classp);
        // The basic randomization (__VBasicRand, or __VBasicRandVars of a class whose basic
        // randomization is split), for repeating it in rounds
        AstFunc* const basicRandomizeFuncp
            = VN_AS(VN_AS(basicRandomizeFuncCallp, FuncRef)->taskp(), Func);
        AstVar* const localGenp
            = new AstVar{nodep->fileline(), VVarType::BLOCKTEMP, "randomizer",
                         classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)};
        localGenp->funcLocal(true);

        // Last statement before the solve, which starts with registering the arrays' elements
        AstNode* const solveAfterp
            = randomizeFuncp->stmtsp() ? randomizeFuncp->stmtsp()->lastp() : nullptr;
        // Add constraints clearing code
        if (classGenp) {
            randomizeFuncp->addStmtsp(
                implementConstraintsClear(randomizeFuncp->fileline(), classGenp));
        }

        randomizeFuncp->addDeclsp(localGenp);

        // Copy (derive) class constraints if present
        if (classGenp) {
            AstTask* const constrSetupFuncp
                = SmtUtil::getCreateConstraintSetupFunc(classp, m_memberMap);
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
        AstVar* const randModeVarp = RandModeVars::randModeVarp(classp);
        if (!classGenp && randModeVarp) addSetRandMode(randomizeFuncp, localGenp, randModeVarp);
        if (!classGenp) {
            if (AstVar* const sVarp = getStaticRandModeVar(classp)) {
                addSetStaticRandMode(randomizeFuncp, localGenp, sVarp);
            }
        }

        // Generate constraint setup code and a hardcoded call to the solver
        AstBegin* const holderp = SmtUtil::newItemsHolderp(nodep->fileline(), capturedTreep);
        AstBegin* const setupBlockp
            = new AstBegin{nodep->fileline(), "__Vsetup_constraints", holderp, true};
        // Analyze before dist loses its membership/weight/soft-priority structure.
        randomizeFuncp->addStmtsp(FastConstraintBuilder::apply(holderp->declsp(), localGenp));
        // Dist bucket draws go into the function, ahead of the constraints reading them
        lowerDistConstraints(randomizeFuncp, VN_AS(holderp->declsp(), NodeConstraintItem),
                             randModeVarp);
        capturedTreep = holderp->declsp();
        randomizeFuncp->addStmtsp(setupBlockp);
        // With a class generator the class setup above added them
        if (!classGenp) {
            if (AstNodeStmt* const pinsp = newClassElemModePinsp(classp, localGenp)) {
                randomizeFuncp->addStmtsp(pinsp);
            }
        }

        // Pre-scan captured tree for .size on dynamic arrays and queues and replace
        // with size variables, using shared createOrGetSizeVar helper.
        // After CaptureVisitor, fromp() of .size is AstMemberRef (not VarRef),
        // so extract the underlying variable from the MemberRef chain.
        // Collect the class-wide resize call and the with-block's own resize
        // statements to run after a successful solver call.
        AstNodeStmt* resizeStmtsp = nullptr;
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
                // Extract array variable from fromp (VarRef or MemberRef after capture)
                AstVar* arrVarp = nullptr;
                AstNodeExpr* const rootExprp = methodp->fromp();
                if (AstMemberRef* memberRefp = VN_CAST(rootExprp, MemberRef)) {
                    arrVarp = memberRefp->varp();
                    // A non-random array is not randomized however it is reached (IEEE
                    // 1800-2023 18.4), so its size is a state value
                    if (!arrVarp->rand().isRandomizable()) continue;
                    while (VN_IS(memberRefp->fromp(), MemberRef)) {
                        memberRefp = VN_CAST(memberRefp->fromp(), MemberRef);
                    }
                    // Only variables that are part of object that randomize is called on shall be
                    // randomized (18.6.1), skip randomization if deepest variable is reference to
                    // __Vthis
                    const AstNodeExpr* const fromp = memberRefp->fromp();
                    if (const AstVarRef* const varRefp = VN_CAST(fromp, VarRef)) {
                        if (varRefp->varp() == thisVarp) continue;
                    } else {
                        fromp->v3warn(E_UNSUPPORTED, "Unsupported: Unsupported size constraint "
                                                     "inside 'with' statement of type "
                                                         << fromp->dtypep()->prettyTypeNameQ());
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
                const bool viaMember = VN_IS(rootExprp, MemberRef);
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
                    AstNodeExpr* const resizeVarRefp = buildMemberRefExprp(rootExprp, arrVarp);
                    if (viaMember)
                        memberArrays.emplace(memberPath, VN_AS(resizeVarRefp, MemberRef));
                    AstNodeExpr* const sizeExprp = buildMemberRefExprp(rootExprp, sizeVarp);
                    // Append size >= 0 constraint so ConstraintExprVisitor processes it
                    capturedTreep->addNext(createSizeGteZeroConstraint(fl, sizeVarp, rootExprp));
                    AstCMethodHard* const resizep
                        = new AstCMethodHard{fl, resizeVarRefp, VCMethod::DYN_RESIZE, sizeExprp};
                    resizep->dtypep(methodp->findVoidDType());
                    resizeStmtsp = AstNode::addNext(resizeStmtsp, new AstStmtExpr{fl, resizep});
                }
                AstNodeExpr* const sizeNodeExprp = buildMemberRefExprp(rootExprp, sizeVarp);
                methodp->replaceWith(sizeNodeExprp);
                VL_DO_DANGLING(methodp->deleteTree(), methodp);
            }
        }

        // Keep an independent copy of the lowered with-block constraints to rebuild
        // them against post-resize arrays if a size phase is needed below.
        AstBegin* const capturedClonep
            = SmtUtil::newItemsHolderp(nodep->fileline(), cloneWithDistPreambles(capturedTreep));

        // Arrays that gain a size var from THIS with-block's own inline .size()==expr
        // constraint (as opposed to a class-level one) and are also referenced by a
        // unique{} constraint here; see the m_sizeConstrainedArraysp comment in
        // ConstraintExprVisitor::visit(AstConstraintUnique). Merged below with any
        // class-level size-constrained arrays.
        VInsertionSet<AstVar*> allSizeArrays;
        expandUniqueElementList(holderp->declsp());
        const ConstraintExprVisitor exprVisitor{
            classp,        m_memberMap,  holderp->declsp(), setupBlockp,
            localGenp,     randModeVarp, m_writtenVars,     &m_uniqueConstraintId,
            m_uniqueNames, nullptr,      &allSizeArrays};
        SmtUtil::replaceWithLowered(holderp);

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
        AstVar* const retVarp = randomizeFuncp->fvarp();
        // Arrays whose size this call solves; each is pinned when frozen and for the final solve
        VInsertionSet<AstVar*> sizedArrays = pinnedArrays;
        sizedArrays.insert(inlineSizedArrays.begin(), inlineSizedArrays.end());
        addFrozenSizePins(sizedArrays, memberArrays, randomizeFuncp, localGenp, randModeVarp);

        if (needsSizePhase) {
            AstVar* const finalOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vfinal_ok",
                                                   classp->findBasicDType(VBasicDTypeKwd::BIT)};
            finalOkVarp->funcLocal(true);
            randomizeFuncp->addDeclsp(finalOkVarp);

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

            // Call the basic randomization as its own statement after the resize, so it fills
            // the new elements, and before the final solve, so the solver's answer sticks.
            // The single-statement form below (basicRandomizeFuncCallp combined inline
            // with the solver call) relies on statement hoisting for that order, which
            // would place it after the final solve here.
            AstVar* const basicOkVarp = new AstVar{fl, VVarType::BLOCKTEMP, "__Vbasic_ok",
                                                   classp->findBasicDType(VBasicDTypeKwd::BIT)};
            basicOkVarp->funcLocal(true);
            randomizeFuncp->addDeclsp(basicOkVarp);
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
                    = SmtUtil::getCreateConstraintSetupFunc(classp, m_memberMap);
                randomizeFuncp->addStmtsp((new AstTaskRef{fl, constrSetupFuncp2})->makeStmt());
                // The copy keeps the randc cycles of this call, as its size solve left them
                AstVar* const randcKeepp
                    = randcHistoryp
                          ? new AstVar{fl, VVarType::BLOCKTEMP, "__Vrandc_keep",
                                       classp->findBasicDType(VBasicDTypeKwd::RANDOM_GENERATOR)}
                          : nullptr;
                if (randcKeepp) {
                    randcKeepp->funcLocal(true);
                    randomizeFuncp->addDeclsp(randcKeepp);
                    randomizeFuncp->addStmtsp(newRandcHistoryFromp(fl, randcKeepp, localGenp));
                }
                randomizeFuncp->addStmtsp(
                    new AstAssign{fl, new AstVarRef{fl, localGenp, VAccess::WRITE},
                                  new AstVarRef{fl, VN_AS(classGenp->user2p(), NodeModule),
                                                classGenp, VAccess::READ}});
                if (randcKeepp) {
                    randomizeFuncp->addStmtsp(newRandcHistoryFromp(fl, localGenp, randcKeepp));
                }
            } else if (AstNodeStmt* const pinsp = newClassElemModePinsp(classp, localGenp)) {
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
                const AstMemberRef* const mselp = pathMsel.second;
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
                if (!allSizeArrays.exists(arrVarp))
                    continue;  // Elements left to basic randomization

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

                const size_t width = RandomizeUtil::arrayElementDTypep(arrVarp->dtypep())->width();
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
            expandUniqueElementList(capturedClonep->declsp());
            ConstraintExprVisitor{classp,
                                  m_memberMap,
                                  capturedClonep->declsp(),
                                  elementSetupBlockp,
                                  localGenp,
                                  randModeVarp,
                                  m_writtenVars,
                                  &m_uniqueConstraintId,
                                  m_uniqueNames,
                                  nullptr};
            SmtUtil::replaceWithLowered(capturedClonep);

            // Pin the sizes so the final solve can't move them
            for (AstVar* const arrVarp : sizedArrays) {
                randomizeFuncp->addStmtsp(newPinSizeVariable(fl, arrVarp, localGenp));
            }

            for (const auto& pathMsel : memberArrays) {
                const AstMemberRef* const mselp = pathMsel.second;
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
            // Preambles held in user3p are off-tree, so are not freed with the copy
            deleteDistPreambles(capturedClonep);
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
                randomizeFuncp,
                solveAfterp ? VN_AS(solveAfterp->nextp(), NodeStmt) : randomizeFuncp->stmtsp(),
                classGenp ? classGenp : localGenp, localGenp, retVarp, basicRandomizeFuncp, calls,
                classGenp ? nullptr : implementConstraintsClear(fl, localGenp));
        }
        // A failed call leaves the randc cycles alone
        if (randcHistoryp) {
            randomizeFuncp->addStmtsp(
                new AstIf{fl, new AstVarRef{fl, retVarp, VAccess::READ},
                          newRandcHistoryFromp(fl, randcHistoryp, localGenp)});
        }
    }
    AstNodeExpr* lowerStdRandomizeWith(AstNodeFTaskRef* nodep, AstFunc* randomizeFuncp,
                                       AstNode* capturedTreep, AstVar* stdrandp) override {
        FileLine* const fl = nodep->fileline();
        // Clear old constraints and variables for std::randomize with clause
        AstNodeStmt* const roundsFirstp
            = implementConstraintsClearAll(randomizeFuncp->fileline(), stdrandp);
        randomizeFuncp->addStmtsp(roundsFirstp);
        AstBegin* const holderp = SmtUtil::newItemsHolderp(fl, capturedTreep);
        AstBegin* const setupBlockp = new AstBegin{fl, "__Vsetup_constraints", holderp, true};
        // Selected pieces may be marshalled through distinct temporaries despite
        // aliasing the same SV storage. Only direct scalar arguments use this path.
        bool fastArgs = true;
        for (const AstArg* const argp : nodep->argspList()) {
            const AstNodeExpr* const exprp = argp->exprp();
            fastArgs &= VN_IS(exprp, VarRef) || VN_IS(exprp, MemberRef);
        }
        randomizeFuncp->addStmtsp(
            FastConstraintBuilder::apply(holderp->declsp(), stdrandp, fastArgs));
        lowerDistConstraints(randomizeFuncp, VN_AS(holderp->declsp(), NodeConstraintItem),
                             nullptr);
        randomizeFuncp->addStmtsp(setupBlockp);
        expandUniqueElementList(holderp->declsp());
        const ConstraintExprVisitor exprVisitor{
            nullptr, m_memberMap,   holderp->declsp(),     setupBlockp,   stdrandp,
            nullptr, m_writtenVars, &m_uniqueConstraintId, m_uniqueNames, nullptr};
        SmtUtil::replaceWithLowered(holderp);
        m_stdFuncRounds[randomizeFuncp] = StdFuncRounds{roundsFirstp, exprVisitor.funcCalls()};
        AstCExpr* const solverCallp = new AstCExpr{fl};
        solverCallp->dtypeSetBit();
        solverCallp->add(new AstVarRef{fl, stdrandp, VAccess::READWRITE});
        solverCallp->add(".next()");
        return solverCallp;
    }
    void finishStdRandomizeWith(AstFunc* randomizep, AstVar* stdrandp) override {
        const auto it = m_stdFuncRounds.find(randomizep);
        UASSERT_OBJ(it != m_stdFuncRounds.end(), randomizep, "Missing std::randomize lowering");
        addFuncRounds(randomizep, it->second.firstp, stdrandp, stdrandp, randomizep->fvarp(),
                      nullptr, it->second.calls);
        m_stdFuncRounds.erase(it);
    }
    void prepareInlineRandomize(AstClass* classp,
                                const std::function<void(AstClass*)>& lowerClass) override {
        // Lowering the derived classes can lower a nested 'randomize() with' of the same class,
        // which takes its entry, so get the calls before the entry
        std::vector<ConstraintFuncCall> calls = derivedFuncCalls(classp, lowerClass);
        m_inlineDerivedCalls[classp] = std::move(calls);
    }
    AstNodeExpr* lowerCheckOnly(AstClass* classp, AstFunc* funcp) override {
        FileLine* const fl = classp->fileline();
        AstVar* const classGenp = SmtUtil::getRandomGenerator(classp);
        if (!classGenp) return new AstConst{fl, AstConst::WidthedValue{}, 32, 1};
        // Register the variables as new() and randomize() do, so arrays have their current
        // elements, and set the size variables the solver checks array sizes with
        VInsertionSet<AstVar*> sizedArrays;
        for (AstClass* cp = classp; cp; cp = cp->extendsp() ? cp->extendsp()->classp() : nullptr) {
            copyVariableRegistrations(VN_AS(m_memberMap.findMember(cp, "new"), Func), funcp);
            for (AstVar* const arrVarp : m_sizeConstrainedArrays[cp]) sizedArrays.insert(arrVarp);
        }
        // Arrays with only a size constraint, and arrays of member objects, also have one
        MemberArrays memberArrays;
        addResizedArrays(classp, sizedArrays, memberArrays);
        for (AstVar* const arrVarp : sizedArrays) funcp->addStmtsp(newSizeVarAssign(fl, arrVarp));
        for (const auto& pathMsel : memberArrays) {
            const AstMemberRef* const mselp = pathMsel.second;
            funcp->addStmtsp(newIfNonNullp(fl, newSizeVarAssign(fl, mselp->varp(), mselp), mselp));
        }
        AstNodeModule* const genModp = VN_AS(classGenp->user2p(), NodeModule);
        funcp->addStmtsp(implementConstraintsClear(fl, classGenp));
        AstTask* const setupAllTaskp = SmtUtil::getCreateConstraintSetupFunc(classp, m_memberMap);
        funcp->addStmtsp((new AstTaskRef{fl, setupAllTaskp})->makeStmt());
        AstCExpr* const solverCallp = new AstCExpr{fl};
        solverCallp->dtypeSetBit();
        solverCallp->add(new AstVarRef{fl, genModp, classGenp, VAccess::READWRITE});
        solverCallp->add(".next_check_only(__Vm_rng)");
        classp->needRNG(true);
        return solverCallp;
    }
};

//######################################################################
// V3SolverSmt class functions

std::unique_ptr<V3SolverLowering>
V3SolverSmt::newLowering(VMemberMap& memberMap, V3UniqueNames& uniqueNames,
                         const RandModeVars& modeVars, ElemRandModes& elemModes,
                         const ClonedConstraints& cloneObjps, VNDeleter& deleter) const {
    return std::unique_ptr<V3SolverLowering>{
        new SolverSmtLowering{memberMap, uniqueNames, modeVars, elemModes, cloneObjps, deleter}};
}

std::vector<std::string> V3SolverSmt::runtimeCFlags() const {
    std::vector<std::string> cflags;
    const std::string solver = V3Options::getenvVERILATOR_SOLVER();
    if (solver != "") {
        cflags.emplace_back("-DVM_SOLVER_DEFAULT='\"" + V3OutFormatter::quoteNameControls(solver)
                            + "\"'");
    }
    const std::string sampler = V3Options::getenvVERILATOR_RAND_SAMPLER();
    if (sampler != "") {
        cflags.emplace_back("-DVM_RAND_SAMPLER_DEFAULT='\""
                            + V3OutFormatter::quoteNameControls(sampler) + "\"'");
    }
    return cflags;
}
