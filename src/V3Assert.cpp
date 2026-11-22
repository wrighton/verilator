// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Collect and print statistics
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2005-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3Assert.h"

#include "V3Const.h"
#include "V3Stats.h"
#include "V3Task.h"
#include "V3UniqueNames.h"
#include "V3VNUserAllocator.h"

VL_DEFINE_DEBUG_FUNCTIONS;

namespace {

class DefaultDisableLocalVisitor final : public VNVisitor {
    // STATE
    AstNode* m_scopep = nullptr;

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        nodep->defaultDisablep(nullptr);
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_scopep);
        m_scopep = nodep;
        nodep->defaultDisablep(nullptr);
        iterateChildren(nodep);
    }
    void visit(AstDefaultDisable* nodep) override {
        UASSERT_OBJ(nodep, m_scopep,
                    "default disable iff must be inside a module or generate block");
        AstDefaultDisable* defaultp = nullptr;
        if (const AstNodeModule* const modp = VN_CAST(m_scopep, NodeModule)) {
            defaultp = modp->defaultDisablep();
        } else {
            defaultp = VN_AS(m_scopep, GenBlock)->defaultDisablep();
        }
        if (VL_UNLIKELY(defaultp)) {
            nodep->v3error("Only one 'default disable iff' allowed per "
                           << (VN_IS(m_scopep, NodeModule) ? "module" : "generate block")
                           << " (IEEE 1800-2023 16.15)");
        } else if (AstNodeModule* const modp = VN_CAST(m_scopep, NodeModule)) {
            modp->defaultDisablep(nodep);
        } else {
            VN_AS(m_scopep, GenBlock)->defaultDisablep(nodep);
        }
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit DefaultDisableLocalVisitor(AstNetlist* nodep) { iterate(nodep); }
};

class DefaultDisablePropagateVisitor final : public VNVisitor {
    // STATE
    AstDefaultDisable* m_defaultDisablep = nullptr;

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        m_defaultDisablep = nodep->defaultDisablep();
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        VL_RESTORER(m_defaultDisablep);
        if (!nodep->defaultDisablep()) nodep->defaultDisablep(m_defaultDisablep);
        m_defaultDisablep = nodep->defaultDisablep();
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit DefaultDisablePropagateVisitor(AstNetlist* nodep) { iterate(nodep); }
};

}  // namespace

void V3AssertCommon::collectDefaultDisable(AstNetlist* nodep) {
    { DefaultDisableLocalVisitor{nodep}; }
    { DefaultDisablePropagateVisitor{nodep}; }
}

AstClocking* V3AssertCommon::moduleDefaultClockingp(const AstNodeModule* modp) {
    // It applies to the whole module, also to items before its declaration (IEEE 1800-2023 14.12)
    for (AstNode* stmtp = modp->stmtsp(); stmtp; stmtp = stmtp->nextp()) {
        AstClocking* const clockingp = VN_CAST(stmtp, Clocking);
        if (clockingp && clockingp->isDefault()) return clockingp;
    }
    return nullptr;
}

AstVar* V3AssertCommon::newSequenceEvent(FileLine* flp, AstNodeModule* modp, const string& name,
                                         AstSchemaRef* schemaRefp) {
    // The event is fired by an internal cover sequence (IEEE 1800-2023 9.4.2.4)
    AstVar* const eventp
        = new AstVar{flp, VVarType::MODULETEMP, name, modp->findBasicDType(VBasicDTypeKwd::EVENT)};
    eventp->lifetime(VLifetime::STATIC_EXPLICIT);
    modp->addStmtsp(eventp);
    v3Global.setHasEvents();
    if (!schemaRefp) return eventp;
    AstFireEvent* const firep
        = new AstFireEvent{flp, new AstVarRef{flp, eventp, VAccess::WRITE}, false};
    AstCover* const coverp = new AstCover{flp, new AstPropSpec{flp, nullptr, nullptr, schemaRefp},
                                          firep, VAssertType::CONCURRENT};
    coverp->isCoverSeq(true);
    coverp->isSeqEvent(true);
    // A concurrent assertion is in its own process, clocked by it in AssertVisitor
    modp->addStmtsp(new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, coverp});
    return eventp;
}

string V3AssertCommon::assertCtlGetCall(const char* query, VAssertType type,
                                        VAssertDirectiveType directiveType) {
    // Template arguments let the runtime build the type/directive mask at C++ compile time.
    // Parenthesized, so the template comma cannot split an argument of an emitted macro.
    return "(vlSymsp->_vm_contextp__->assertCtlGet<"s + std::to_string(type) + ", "s
           + std::to_string(directiveType) + ">(VerilatedAssertCtlQuery::"s + query + "))"s;
}

AstNodeExpr* V3AssertCommon::newAssertCtlGetp(FileLine* flp, const char* query, VAssertType type,
                                              VAssertDirectiveType directiveType, AstVar* statep) {
    const int width = std::strcmp(query, "ASSERT_CTL_KILL") == 0 ? 32 : 1;
    if (!statep)
        return new AstCExpr{flp, AstCExpr::Pure{}, assertCtlGetCall(query, type, directiveType),
                            width};
    AstCExpr* const exprp = new AstCExpr{flp, AstCExpr::Pure{}, "", width};
    exprp->add(new AstVarRef{flp, statep, VAccess::READ});
    exprp->add(".get(VerilatedAssertCtlQuery::" + string{query} + ")");
    return exprp;
}

bool V3AssertCommon::isSampledType(const AstNodeDType* dtypep) {
    // An integral type, or an unpacked array or structure of such types (IEEE 1800-2023 16.9.3).
    dtypep = dtypep->skipRefp();
    if (dtypep->isIntegralOrPacked()) return true;
    if (const AstUnpackArrayDType* const arrayp = VN_CAST(dtypep, UnpackArrayDType)) {
        return isSampledType(arrayp->subDTypep());
    }
    const AstStructDType* const structp = VN_CAST(dtypep, StructDType);
    if (!structp) return false;
    for (const AstMemberDType* memberp = structp->membersp(); memberp;
         memberp = VN_AS(memberp->nextp(), MemberDType)) {
        if (!isSampledType(memberp->subDTypep())) return false;
    }
    return true;
}

bool V3AssertCommon::checkSvaValueLimit(AstNode* nodep, const AstConst* constp, const char* what) {
    // Temporal values can materialize as O(N) AST or state in later passes.
    // Leave headroom for a range ring's extra slot and V3Number's signed
    // `(bits + 31) / 32` word count.
    static constexpr unsigned SVA_VALUE_HARD_LIMIT
        = static_cast<unsigned>(std::numeric_limits<int>::max()) - 32U;
    const unsigned configuredLimit = static_cast<unsigned>(v3Global.opt.maxNumWidth());
    const unsigned limit = std::min(configuredLimit, SVA_VALUE_HARD_LIMIT);
    if (constp->num().fitsInUInt() && constp->toUInt() <= limit) return true;
    nodep->v3warn(E_UNSUPPORTED, "Unsupported: " << what << " exceeds implementation limit of "
                                                 << limit
                                                 << (configuredLimit <= SVA_VALUE_HARD_LIMIT
                                                         ? " (--max-num-width)"
                                                         : " (host arithmetic limit)"));
    return false;
}

// The bound of a cycle delay in a sequence, if a non-negative elaboration-time constant
static const AstConst* checkSvaDelayBound(AstNode* errp, AstNodeExpr* boundp, const char* what) {
    const AstConst* const constp = VN_CAST(boundp, Const);
    if (!constp || (constp->dtypep()->isSigned() && constp->num().isNegative())) {
        errp->v3error(what << " is not a non-negative elaboration-time constant"
                              " (IEEE 1800-2023 16.7)");
        return nullptr;
    }
    if (!V3AssertCommon::checkSvaValueLimit(errp, constp, "SVA cycle delay")) return nullptr;
    return constp;
}

// Fold the bounds of a cycle delay in a sequence, and return if they are valid, else report it
// on errp
static bool svaCycleDelayValid(const AstDelay* nodep, AstNode* errp) {
    V3Const::constifyParamsNoWarnEdit(nodep->lhsp());
    const AstConst* const minConstp = checkSvaDelayBound(
        errp, nodep->lhsp(), nodep->isRangeDelay() ? "Range delay minimum" : "Delay value");
    if (!nodep->rhsp() || nodep->isUnbounded()) return minConstp != nullptr;
    V3Const::constifyParamsNoWarnEdit(nodep->rhsp());
    const AstConst* const maxConstp
        = checkSvaDelayBound(errp, nodep->rhsp(), "Range delay maximum");
    if (!minConstp || !maxConstp) return false;
    if (maxConstp->toUInt() < minConstp->toUInt()) {
        errp->v3error("Range delay maximum must be >= minimum (IEEE 1800-2023 16.7)");
        return false;
    }
    return true;
}

void V3AssertCommon::checkSvaCycleDelay(AstDelay* nodep, AstNode* errp) {
    if (svaCycleDelayValid(nodep, errp)) return;
    // Make the delay valid, so later steps do not fail after the error
    FileLine* const flp = nodep->fileline();
    AstNodeExpr* const minp = nodep->lhsp();
    minp->replaceWith(new AstConst{flp, AstConst::BitFalseErroring{}});
    VL_DO_DANGLING(minp->deleteTree(), minp);
    if (nodep->rhsp() && !nodep->isUnbounded()) {
        AstNodeExpr* const maxp = nodep->rhsp();
        maxp->replaceWith(new AstConst{flp, AstConst::BitFalseErroring{}});
        VL_DO_DANGLING(maxp->deleteTree(), maxp);
    }
}

// Replace an invalid repetition count, so later steps do not fail, or expand it, after the error
static void replaceSvaRepCount(AstNodeExpr* countp) {
    countp->replaceWith(new AstConst{countp->fileline(), 1});
    VL_DO_DANGLING(countp->deleteTree(), countp);
}

void V3AssertCommon::checkSvaRepetition(AstSConsRep* nodep, AstNode* errp, bool emptyOk) {
    if (VN_IS(nodep->maxCountp(), Unbounded)) {
        // A '$' actual argument (IEEE 1800-2023 16.8), as [*N:$]
        AstSConsRep* const newp
            = new AstSConsRep{nodep->fileline(), nodep->exprp()->unlinkFrBack(),
                              nodep->countp()->unlinkFrBack(), nullptr, true};
        newp->dtypeFrom(nodep);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(nodep->deleteTree(), nodep);
        nodep = newp;
    }
    // The counts must be valid elaboration-time constants.
    V3Const::constifyParamsEdit(nodep->countp());
    const AstConst* minConstp = VN_CAST(nodep->countp(), Const);
    if (!minConstp) {
        errp->v3error("Consecutive repetition count must be constant expression"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (minConstp->toSInt() < 0) {
        errp->v3error("Consecutive repetition count must be non-negative"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (checkSvaValueLimit(errp, minConstp, "SVA repetition count")) {
        if (!nodep->unbounded() && !nodep->maxCountp() && minConstp->toSInt() < 1 && !emptyOk) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: [*0] consecutive repetition");
        }
    } else {
        minConstp = nullptr;  // Over the limit
    }
    if (!minConstp) replaceSvaRepCount(nodep->countp());
    if (!nodep->maxCountp()) return;
    V3Const::constifyParamsEdit(nodep->maxCountp());
    const AstConst* const maxConstp = VN_CAST(nodep->maxCountp(), Const);
    if (!maxConstp) {
        errp->v3error("Consecutive repetition max count must be constant"
                      " expression (IEEE 1800-2023 16.9.2)");
    } else if (minConstp && maxConstp->toSInt() < minConstp->toSInt()) {
        errp->v3error("Consecutive repetition max count must be >= min count"
                      " (IEEE 1800-2023 16.9.2)");
    } else if (checkSvaValueLimit(errp, maxConstp, "SVA repetition count")) {
        if (maxConstp->toSInt() < 1 && !emptyOk) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: [*N:0] consecutive repetition"
                                        " with zero max count");
        }
        return;
    }
    // The min count is then at most 1 too
    replaceSvaRepCount(nodep->maxCountp());
    if (minConstp) replaceSvaRepCount(nodep->countp());
}

// Goto repetition [->N] or nonconsecutive repetition [=N], with the kind named in messages
template <typename T_Rep>
static void checkSvaGotoOrNonConsRep(T_Rep* nodep, const char* kind, AstNode* errp) {
    // Replace a non-constant count after reporting it, so later steps do not fail.
    if (!nodep->maxCountp()) {
        V3Const::constifyParamsNoWarnEdit(nodep->countp());
        const AstConst* const constp = VN_CAST(nodep->countp(), Const);
        if (!constp) {
            errp->v3error("Repetition count is not an elaboration-time constant"
                          " (IEEE 1800-2023 16.9.2)");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->dtypep()->isSigned() && constp->num().isNegative()) {
            errp->v3error("Repetition count must be non-negative"
                          " (IEEE 1800-2023 16.9.2)");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->num().mostSetBitP1() > 31) {
            errp->v3warn(
                E_UNSUPPORTED,
                "Unsupported: SVA repetition count exceeds implementation limit of 2147483647");
            replaceSvaRepCount(nodep->countp());
        } else if (constp->isZero()) {
            errp->v3warn(E_UNSUPPORTED, "Unsupported: zero repetition count"
                                        " (IEEE 1800-2023 16.9.2)");
        }
        return;
    }
    // A '$' maximum is legal, but is not an expression to constify
    const bool unbounded = VN_IS(nodep->maxCountp(), Unbounded);
    // Accessors are re-fetched after constifyParamsEdit, as it can replace the node in-tree
    V3Const::constifyParamsEdit(nodep->countp());
    if (!unbounded) V3Const::constifyParamsEdit(nodep->maxCountp());
    const AstConst* const minConstp = VN_CAST(nodep->countp(), Const);
    const AstConst* const maxConstp = VN_CAST(nodep->maxCountp(), Const);
    if (!minConstp || (!maxConstp && !unbounded)) {
        errp->v3error(std::string{kind}
                      + " repetition range bounds must be constant expressions"
                        " (IEEE 1800-2023 16.9.2)");
        if (!minConstp) replaceSvaRepCount(nodep->countp());
        if (!maxConstp && !unbounded) replaceSvaRepCount(nodep->maxCountp());
    } else if (minConstp->toSInt() < 0) {
        errp->v3error(std::string{kind}
                      + " repetition range min count must be non-negative"
                        " (IEEE 1800-2023 16.9.2)");
        replaceSvaRepCount(nodep->countp());
        if (!unbounded) replaceSvaRepCount(nodep->maxCountp());
    } else if (unbounded) {
        // Only ever written in the body, as a '$' actual argument is checked when substituted
        nodep->maxCountp()->v3warn(E_UNSUPPORTED,
                                   "Unsupported: " << kind
                                                   << " repetition range with '$' maximum"
                                                      " (IEEE 1800-2023 16.9.2)");
    } else if (maxConstp->toSInt() < minConstp->toSInt()) {
        errp->v3error(std::string{kind}
                      + " repetition range max count must be >= min count"
                        " (IEEE 1800-2023 16.9.2)");
        replaceSvaRepCount(nodep->countp());
        replaceSvaRepCount(nodep->maxCountp());
    } else if (minConstp->isZero()) {
        errp->v3warn(E_UNSUPPORTED, "Unsupported: zero min count in "s + kind
                                        + " repetition range (IEEE 1800-2023 16.9.2)");
    }
}
void V3AssertCommon::checkSvaRepetition(AstSGotoRep* nodep, AstNode* errp) {
    checkSvaGotoOrNonConsRep(nodep, "Goto", errp);
}
void V3AssertCommon::checkSvaRepetition(AstSNonConsRep* nodep, AstNode* errp) {
    checkSvaGotoOrNonConsRep(nodep, "Nonconsecutive", errp);
}

void V3AssertCommon::checkSvaPastTicks(AstPast* nodep, AstNode* errp) {
    // The tick count must be a positive elaboration-time constant, else it is removed after
    // reporting it.
    V3Const::constifyParamsEdit(nodep->ticksp());  // ticksp may change
    const AstConst* const constp = VN_CAST(nodep->ticksp(), Const);
    if (!constp) {
        errp->v3error("$past tick value must be constant (IEEE 1800-2023 16.9.3)");
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (constp->toSInt() < 1) {
        constp->v3error("$past tick value must be >= 1 (IEEE 1800-2023 16.9.3)");
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (!checkSvaValueLimit(nodep, constp, "$past tick value")) {
        nodep->ticksp()->unlinkFrBack()->deleteTree();
    } else if (constp->toSInt() > 10) {
        constp->v3warn(TICKCOUNT, "$past tick value of " << constp->toSInt()
                                                         << " may have a large performance cost");
    }
}

void V3AssertCommon::checkSvaAlwaysRange(AstPropAlways* nodep, AstNode* instp) {
    // Errors are reported on instp if given, else on the bound. After an error the bounds are
    // replaced with constants, so later steps do not fail.
    V3Const::constifyParamsEdit(nodep->loBoundp());  // loBoundp may change
    const bool hiUnbounded = VN_IS(nodep->hiBoundp(), Unbounded);
    if (!hiUnbounded) V3Const::constifyParamsEdit(nodep->hiBoundp());  // hiBoundp may change
    AstNode* const loErrp = instp ? instp : nodep->loBoundp();
    AstNode* const hiErrp = instp ? instp : nodep->hiBoundp();
    const AstConst* const loConstp = VN_CAST(nodep->loBoundp(), Const);
    const AstConst* const hiConstp = VN_CAST(nodep->hiBoundp(), Const);
    bool valid = false;
    if (!loConstp) {
        loErrp->v3error("always range low bound must be a constant expression"
                        " (IEEE 1800-2023 16.12.11)");
    } else if (loConstp->toSInt() < 0) {
        loErrp->v3error("always range low bound must be non-negative"
                        " (IEEE 1800-2023 16.12.11)");
    } else {
        valid = checkSvaValueLimit(loErrp, loConstp, "always range bound");
    }
    if (hiUnbounded && nodep->isStrong()) {
        // From a '$' actual argument (IEEE 1800-2023 16.8)
        hiErrp->v3error("s_always range must be bounded (IEEE 1800-2023 16.12.11)");
        valid = false;
    } else if (hiUnbounded) {
        // Weak always [m:$]
    } else if (!hiConstp) {
        hiErrp->v3error("always range high bound must be a constant expression"
                        " (IEEE 1800-2023 16.12.11)");
        valid = false;
    } else if (!checkSvaValueLimit(hiErrp, hiConstp, "always range bound")) {
        valid = false;
    } else if (loConstp && hiConstp->toSInt() < loConstp->toSInt()) {
        hiErrp->v3error("always range high bound must be >= low bound"
                        " (IEEE 1800-2023 16.12.11)");
        valid = false;
    }
    if (valid) return;
    for (AstNodeExpr* const boundp : {nodep->loBoundp(), nodep->hiBoundp()}) {
        if (VN_IS(boundp, Unbounded) && !nodep->isStrong()) continue;
        boundp->replaceWith(new AstConst{boundp->fileline(), AstConst::BitFalseErroring{}});
        VL_DO_DANGLING(boundp->deleteTree(), boundp);
    }
}

bool V3AssertCommon::refsSvaFormal(const AstNode* nodep) {
    return nodep->exists([](const AstNodeVarRef* refp) {
        const AstVar* const varp = refp->varp();
        if (!varp || !varp->isIO()) return false;
        const AstNode* const declp = varp->aboveLoopp();
        return VN_IS(declp, NodeSchema);
    });
}

AstNode* V3AssertCommon::checkSvaUnboundedActuals(
    AstNode* nodep, const std::unordered_map<const AstVar*, AstNodeExpr*>& portMap,
    AstNode* instp) {
    // A formal argument with a '$' actual argument may only be referenced as the maximum of a
    // cycle_delay_const_range_expression, of a cycle delay, an always, or a repetition, or as the
    // actual argument of a nested instance, which is checked when that is substituted (IEEE
    // 1800-2023 16.8). Run before the substitution, so that a '$' written in the body is not
    // mistaken for one from an actual argument.
    const bool anyUnbounded = std::any_of(portMap.begin(), portMap.end(), [](const auto& it) {
        return VN_IS(it.second, Unbounded);
    });
    if (!anyUnbounded) return nodep;
    std::unordered_set<const AstNode*> legalps;
    nodep->foreach([&](const AstDelay* delayp) {
        if (delayp->rhsp()) legalps.insert(delayp->rhsp());
    });
    nodep->foreach([&](const AstPropAlways* alwaysp) { legalps.insert(alwaysp->hiBoundp()); });
    nodep->foreach([&](const AstSConsRep* repp) { legalps.insert(repp->maxCountp()); });
    // Unlike a literal '$', which they do not support either
    std::unordered_set<const AstNode*> unsupps;
    nodep->foreach([&](const AstSGotoRep* repp) { unsupps.insert(repp->maxCountp()); });
    nodep->foreach([&](const AstSNonConsRep* repp) { unsupps.insert(repp->maxCountp()); });
    nodep->foreach([&](const AstSchemaRef* refp) {
        for (const AstArg* const argp : refp->argspList()) legalps.insert(argp->exprp());
    });
    std::vector<AstVarRef*> badps;
    nodep->foreach([&](AstVarRef* refp) {
        const auto it = portMap.find(refp->varp());
        if (it != portMap.end() && VN_IS(it->second, Unbounded) && !legalps.count(refp)) {
            AstNodeExpr* newp;
            if (unsupps.count(refp)) {
                instp->v3warn(E_UNSUPPORTED, "Unsupported: formal argument "
                                                 << refp->prettyNameQ()
                                                 << " with '$' actual argument as the maximum of a"
                                                    " goto or nonconsecutive repetition range");
                // Make the range its minimum, so later steps do not fail
                const AstSGotoRep* const gotop = VN_CAST(refp->backp(), SGotoRep);
                newp = (gotop ? gotop->countp() : VN_AS(refp->backp(), SNonConsRep)->countp())
                           ->cloneTreePure(false);
            } else {
                instp->v3error("Formal argument " << refp->prettyNameQ()
                                                  << " with '$' actual argument is used other"
                                                     " than as a range maximum (IEEE 1800-2023"
                                                     " 16.8)");
                newp = new AstConst{refp->fileline(), AstConst::BitFalseErroring{}};
            }
            // The body may be only the reference
            if (refp == nodep) {
                nodep = newp;
            } else {
                refp->replaceWith(newp);
            }
            badps.push_back(refp);
        }
    });
    for (AstVarRef* const refp : badps) VL_DO_DANGLING(refp->deleteTree(), refp);
    return nodep;
}

void V3AssertCommon::checkSvaInstanceConstants(AstNode* nodep, AstNode* instp) {
    // Check the cycle delays, repetition counts, always ranges and $past tick counts, now that
    // the formal arguments are replaced with the actual arguments (IEEE 1800-2023 16.8).
    // A delay still referencing a formal argument of an enclosing sequence or property is
    // checked when that is instanced. Collect first, as checking edits the delays.
    std::vector<AstDelay*> delayps;
    nodep->foreach([&](AstDelay* delayp) {
        if (!delayp->isCycleDelay() || refsSvaFormal(delayp->lhsp())) return;
        if (delayp->rhsp() && refsSvaFormal(delayp->rhsp())) return;
        delayps.push_back(delayp);
    });
    for (AstDelay* const delayp : delayps) checkSvaCycleDelay(delayp, instp);
    // Likewise repetitions and $past
    std::vector<AstNodeExpr*> exprps;
    nodep->foreach([&](AstNodeExpr* exprp) {
        const AstPast* const pastp = VN_CAST(exprp, Past);
        if (VN_IS(exprp, SConsRep) || VN_IS(exprp, SGotoRep) || VN_IS(exprp, SNonConsRep)
            || VN_IS(exprp, PropAlways) || (pastp && pastp->ticksp())) {
            if (!refsSvaFormal(exprp)) exprps.push_back(exprp);
        }
    });
    // Inner ones first, as checking an outer one may delete an invalid count holding them
    for (auto it = exprps.rbegin(); it != exprps.rend(); ++it) {
        AstNodeExpr* const exprp = *it;
        if (AstSConsRep* const repp = VN_CAST(exprp, SConsRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstSGotoRep* const repp = VN_CAST(exprp, SGotoRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstSNonConsRep* const repp = VN_CAST(exprp, SNonConsRep)) {
            checkSvaRepetition(repp, instp);
        } else if (AstPropAlways* const alwaysp = VN_CAST(exprp, PropAlways)) {
            checkSvaAlwaysRange(alwaysp, instp);
        } else {
            checkSvaPastTicks(VN_AS(exprp, Past), instp);
        }
    }
}

std::unordered_map<const AstVar*, AstVar*>
V3AssertCommon::newSvaLocalVars(const AstNodeSchema* schemap, AstNodeModule* modp,
                                V3UniqueNames& names) {
    std::unordered_map<const AstVar*, AstVar*> localVarMap;
    for (const AstNode* const declp : schemap->declspList()) {
        const AstVar* const varp = VN_CAST(declp, Var);
        if (!varp || varp->isIO()) continue;
        // An XTEMP stays one, see isMatchItem in V3AssertNfa
        const VVarType varType
            = varp->varType() == VVarType::XTEMP ? VVarType::XTEMP : VVarType::MODULETEMP;
        AstVar* const newVarp
            = new AstVar{varp->fileline(), varType, names.get(varp), varp->dtypep()};
        newVarp->lifetime(VLifetime::STATIC_EXPLICIT);
        modp->addStmtsp(newVarp);
        localVarMap[varp] = newVarp;
    }
    return localVarMap;
}

AstNode* V3AssertCommon::relinkSvaInstanceBody(AstNode* bodyp, const AstSchemaRef* instp) {
    // A sequence or property may be instanced by a hierarchical name (IEEE 1800-2023 16.8,
    // 16.12). Its inlined body then refers to the declaring scope through the same path.
    const string dotted = instp->dotted();
    if (dotted.empty()) return bodyp;
    // Formal arguments and local variables, which are substituted by the caller
    std::unordered_set<const AstVar*> ownVarps;
    for (const AstNode* const declp : instp->schemap()->declspList()) {
        if (const AstVar* const varp = VN_CAST(declp, Var)) ownVarps.insert(varp);
    }
    // A hierarchical reference is downward if it starts at a scope in the declaring module.
    // Others are upward or absolute, so resolve the same from the instance.
    std::unordered_set<string> scopeNames;
    const AstNode* modp = instp->schemap();
    while (!VN_IS(modp, NodeModule)) modp = modp->backp();
    modp->foreach([&](const AstNode* nodep) {
        if (VN_IS(nodep, Cell) || VN_IS(nodep, NodeBlock) || VN_IS(nodep, GenBlock)
            || (VN_IS(nodep, Var) && VN_AS(nodep, Var)->isIfaceRef())) {
            scopeNames.insert(nodep->name());
        }
    });
    const auto relinkDotted = [&](const string& refDotted) {
        if (refDotted.empty()) return dotted;
        if (!scopeNames.count(refDotted.substr(0, refDotted.find('.')))) return refDotted;
        return dotted + "." + refDotted;
    };
    bodyp->foreach([&](AstVarXRef* refp) { refp->dotted(relinkDotted(refp->dotted())); });
    bodyp->foreach([&](AstNodeFTaskRef* refp) {
        if (!refp->classOrPackagep()) refp->dotted(relinkDotted(refp->dotted()));
    });
    bodyp->foreach([&](AstSchemaRef* refp) {
        if (!refp->classOrPackagep()) refp->dotted(relinkDotted(refp->dotted()));
    });
    bodyp->foreach([&](AstVarRef* refp) {
        if (refp->classOrPackagep() || ownVarps.count(refp->varp())) return;
        AstVarXRef* const xrefp
            = new AstVarXRef{refp->fileline(), refp->varp(), dotted, refp->access()};
        if (refp == bodyp) {
            bodyp = xrefp;
        } else {
            refp->replaceWith(xrefp);
        }
        VL_DO_DANGLING(refp->deleteTree(), refp);
    });
    return bodyp;
}

void V3AssertCommon::removeActualReductions(const std::vector<AstNodeExpr*>& actualps) {
    // V3Width reduces a reference to an untyped formal argument used as a boolean, as its type is
    // only known from the actual argument (IEEE 1800-2023 16.8). A sequence or property
    // instance is not an operand of a reduction, and for any other single-bit actual argument the
    // reduction is an identity.
    for (AstNodeExpr* const actualp : actualps) {
        AstRedOr* const redOrp = VN_CAST(actualp->firstAbovep(), RedOr);
        if (!redOrp || actualp->width() != 1) continue;
        redOrp->replaceWith(actualp->unlinkFrBack());
        VL_DO_DANGLING(redOrp->deleteTree(), redOrp);
    }
}

void V3AssertCommon::lowerSvaLocalVarInits(
    AstProperty* propp, AstPropSpec* bodyp,
    const std::unordered_map<const AstVar*, AstVar*>& localVarMap) {
    // A local variable is initialized at the start of each attempt (IEEE 1800-2023 16.10), but
    // its module variable is not. A read that is not after a match item assigning the variable
    // sees the initial value. Here only the reads in the consequent of an implication whose
    // antecedent is `(e, v = x)` are known to follow it; a read after a match item in the same
    // sequence, which V3AssertNfa lowers later, is conservatively reported too.
    const AstImplication* const implp = VN_CAST(bodyp->propp(), Implication);
    const AstExprStmt* const itemsp = implp ? VN_CAST(implp->lhsp(), ExprStmt) : nullptr;
    // V3LinkParse keeps the initializer of a local variable as its value
    for (AstNode* const declp : propp->declspList()) {
        AstVar* const localVarp = VN_CAST(declp, Var);
        if (!localVarp || localVarp->isIO() || !localVarp->valuep()) continue;
        V3Const::constifyParamsNoWarnEdit(localVarp->valuep());  // valuep may change
        AstNodeExpr* const initp = VN_AS(localVarp->valuep(), NodeExpr);
        const AstConst* const constp = VN_CAST(initp, Const);
        const AstVar* const varp = localVarMap.at(localVarp);
        std::vector<AstVarRef*> readps;
        bool assigned = false;
        bodyp->foreach([&](AstVarRef* refp) {
            if (refp->varp() != varp) return;
            if (refp->access().isReadOnly()) {
                readps.push_back(refp);
            } else {
                assigned = true;
            }
        });
        if (assigned) {
            std::unordered_set<const AstVarRef*> beforeps{readps.begin(), readps.end()};
            if (itemsp && itemsp->exists([&](const AstVarRef* refp) {
                    return refp->varp() == varp && refp->access().isWriteOrRW();
                })) {
                implp->rhsp()->foreach([&](const AstVarRef* refp) { beforeps.erase(refp); });
            }
            if (!beforeps.empty()) {
                initp->v3warn(E_UNSUPPORTED,
                              "Unsupported: initializer of a property local variable"
                              " assigned by a match item, read other than in the"
                              " consequent of an implication whose antecedent assigns"
                              " it (IEEE 1800-2023 16.10)");
            }
        } else if (constp) {
            for (AstVarRef* const refp : readps) {
                AstConst* const newp = new AstConst{refp->fileline(), constp->num()};
                newp->dtypeFrom(refp);
                refp->replaceWith(newp);
                VL_DO_DANGLING(refp->deleteTree(), refp);
            }  // LCOV_EXCL_LINE -- GCC exception cleanup branch
        } else if (!readps.empty()) {
            initp->v3warn(E_UNSUPPORTED, "Unsupported: non-constant initializer of a property"
                                         " local variable (IEEE 1800-2023 16.10)");
        }
    }
}

void V3AssertCommon::reducePlainAlways(AstPropSpec* specp) {
    // Equivalent when the property is attempted at every tick (IEEE 1800-2023 16.12.11).
    // Unlike under always, p may then contain property operators.
    AstPropAlways* const alwaysp = VN_CAST(specp->propp(), PropAlways);
    if (!alwaysp || !alwaysp->isPlainAlways()) return;
    alwaysp->replaceWith(alwaysp->propp()->unlinkFrBack());
    VL_DO_DANGLING(alwaysp->deleteTree(), alwaysp);
}

AstSenItem* V3AssertCommon::inferredClock(const AstAlways* alwaysp) {
    // A single edge event none of whose variables is used in the procedure body. A use in an
    // event, as in the clock that assertion lowering gives a sampled value function, is ignored.
    AstSenItem* const itemp = alwaysp->sentreep() ? alwaysp->sentreep()->sensesp() : nullptr;
    if (!itemp || itemp->nextp() || !itemp->edgeType().anEdge() || !alwaysp->stmtsp()) {
        return nullptr;
    }
    const auto inEvent = [alwaysp](const AstNode* nodep) {
        for (; nodep != alwaysp; nodep = nodep->aboveLoopp()) {
            if (VN_IS(nodep, SenItem)) return true;
        }
        return false;
    };
    const bool usedInBody = itemp->sensp()->exists([&](const AstVarRef* clkRefp) {
        return alwaysp->stmtsp()->existsAndNext([&](const AstVarRef* refp) {
            return refp->varp() == clkRefp->varp() && !inEvent(refp);
        });
    });
    return usedInBody ? nullptr : itemp;
}

//######################################################################
// AssertActionXRefVisitor
// Find hierarchical references in an action to its variables whose first name the upward name
// resolution (IEEE 1800-2023 23.8) finds inside the action, so in the current instance: as a
// block enclosing the reference, or a child block of one or of the action. Other paths may
// leave the action and select another instance.

class AssertActionXRefVisitor final : public VNVisitorConst {
    // STATE
    std::unordered_set<const AstVar*> m_declVarps;  // Variables declared in the action
    // Names of the child blocks of each named block (nullptr: the action), through unnamed blocks
    std::unordered_map<const AstNodeBlock*, std::vector<std::string>> m_childNames;
    std::unordered_map<std::string, int> m_visibleNames;  // Count of first names found inside
    const AstNodeBlock* m_blockp = nullptr;  // Enclosing named block (nullptr: the action)
    bool m_collecting = true;  // Collecting m_childNames, else finding references
    std::vector<AstVarXRef*> m_xrefps;  // References found

    void showNames(const AstNodeBlock* blockp, int delta) {
        for (const std::string& name : m_childNames[blockp]) m_visibleNames[name] += delta;
    }

    // VISITORS
    void visit(AstNodeBlock* nodep) override {
        if (nodep->name().empty()) {
            iterateChildrenConst(nodep);
            return;
        }
        if (m_collecting) m_childNames[m_blockp].push_back(nodep->name());
        VL_RESTORER(m_blockp);
        m_blockp = nodep;
        if (!m_collecting) showNames(nodep, 1);
        iterateChildrenConst(nodep);
        if (!m_collecting) showNames(nodep, -1);
    }
    void visit(AstVarXRef* nodep) override {
        if (m_collecting || !m_declVarps.count(nodep->varp())) return;
        const std::string dotted = nodep->dotted();
        if (m_visibleNames[dotted.substr(0, dotted.find('.'))] > 0) m_xrefps.push_back(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildrenConst(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertActionXRefVisitor(AstNodeStmt* actionp) {
        actionp->foreachAndNext([&](const AstVar* const varp) { m_declVarps.emplace(varp); });
        iterateAndNextConstNull(actionp);
        m_collecting = false;
        showNames(nullptr, 1);
        iterateAndNextConstNull(actionp);
    }
    ~AssertActionXRefVisitor() override = default;
    const std::vector<AstVarXRef*>& xrefps() const { return m_xrefps; }
};

// All executions of an action share its static variables, initialized once, and each has its
// own automatic variables (IEEE 1800-2023 6.21). So the clone refers to the original static
// declarations, and renames its automatic ones, which V3Begin may lift to the same scope.
AstNodeStmt* V3AssertCommon::cloneAction(AstNodeStmt* const actionp, V3UniqueNames& names) {
    // V3LinkDot finds hierarchical references again by name, which fails for a clone in
    // another scope, so these refer to their variable directly
    const AssertActionXRefVisitor xrefVisitor{actionp};
    for (AstVarXRef* const xrefp : xrefVisitor.xrefps()) {
        xrefp->replaceWithKeepDType(
            new AstVarRef{xrefp->fileline(), xrefp->varp(), xrefp->access()});
        VL_DO_DANGLING(xrefp->deleteTree(), xrefp);
    }
    AstNodeStmt* const clonep = actionp->cloneTree(true);
    std::unordered_map<const AstVar*, AstVar*> origVarps;  // Cloned to original static variable
    actionp->foreachAndNext([&](AstVar* const varp) {
        if (varp->lifetime().isStatic()) origVarps.emplace(varp->clonep(), varp);
    });
    std::vector<AstNode*> declps;  // Static declarations of the clone
    clonep->foreachAndNext([&](AstNode* const nodep) {
        if (AstNodeVarRef* const refp = VN_CAST(nodep, NodeVarRef)) {
            const auto it = origVarps.find(refp->varp());
            if (it != origVarps.end()) refp->varp(it->second);
        } else if (AstVar* const varp = VN_CAST(nodep, Var)) {
            if (origVarps.count(varp)) {
                declps.push_back(varp);
            } else {
                varp->name(names.get(varp->name()));
            }
        } else if (VN_IS(nodep, Typedef) || VN_IS(nodep, InitialStaticStmt)) {
            declps.push_back(nodep);
        }
    });
    for (AstNode* const nodep : declps) nodep->unlinkFrBack()->deleteTree();
    return clonep;
}

//######################################################################
// AssertDeFutureVisitor
// If any AstFuture, then move all non-future varrefs to be one cycle behind,
// see IEEE 1800-2023 16.9.4.

class AssertDeFutureVisitor final : public VNVisitor {
    // STATE - across all visitors
    AstNodeModule* const m_modp;  // Module future is underneath
    const AstFuture* m_futurep;  // First AstFuture found
    const unsigned m_pastNum;  // Prefix unique number for this module
    std::map<AstVar*, AstVar*> m_delayedVars;  // Old to delayed variable mapping
    std::map<AstVar*, AstVar*> m_delayedDisableVars;  // Same, in the disable condition
    // STATE - for current visit position (use VL_RESTORER)
    bool m_inFuture = false;  // Inside a future
    bool m_inDisable = false;  // Inside a disable condition
    bool m_inSampled = false;  // Inside a sampled value function
    bool m_unsupported = false;  // Printed unsupported

    // METHODS
    void unsupported(AstNode* nodep) {
        if (m_unsupported) return;
        m_unsupported = true;
        nodep->v3warn(E_UNSUPPORTED,
                      "Unsupported/illegal: Future value function used with expression with "
                          << nodep->prettyOperatorName());
    }
    // Return a new variable that each future clock tick loads with 'valuep'
    AstVar* newDelayedVar(const string& name, AstNodeExpr* valuep) {
        FileLine* const flp = valuep->fileline();
        AstAlways* const alwaysp = new AstAlways{flp, VAlwaysKwd::ALWAYS,
                                                 m_futurep->sentreep()->cloneTree(false), nullptr};
        m_modp->addStmtsp(alwaysp);
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, valuep->dtypep()};
        m_modp->addStmtsp(varp);
        AstVarRef* const writeRefp = new AstVarRef{flp, varp, VAccess::WRITE};
        writeRefp->user1(true);
        alwaysp->addStmtsp(new AstAssignDly{flp, writeRefp, valuep});
        return varp;
    }
    // VISITORS
    void visit(AstPropSpec* nodep) override {
        iterateAndNextNull(nodep->sensesp());
        {
            VL_RESTORER(m_inDisable);
            m_inDisable = true;
            iterateAndNextNull(nodep->disablep());
        }
        iterateAndNextNull(nodep->propp());
        iterateAndNextNull(nodep->matchCountp());
    }
    void visit(AstSampled* nodep) override {
        VL_RESTORER(m_inSampled);
        m_inSampled = true;
        iterateChildren(nodep);
    }
    void visit(AstFuture* nodep) override {
        // A disable condition is not a property or sequence expression, so leave a future value
        // function there for AssertVisitor to reject (IEEE 1800-2023 16.9.4)
        if (m_inDisable) return;
        VL_RESTORER(m_inFuture);
        m_inFuture = true;
        iterateChildren(nodep);
        // Done with the future, this subexpression is current-time
        nodep->replaceWith(nodep->exprp()->unlinkFrBack());
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (nodep->user1SetOnce()) return;
        if (m_inFuture || m_unsupported)
            return;  // Need user1 set above, don't process when Future is removed
        if (nodep->access().isWriteOrRW()) {
            unsupported(nodep);
            return;
        }
        // In the disable condition, other than in a sampled value function, the current value
        // (IEEE 1800-2023 16.12)
        const bool current = m_inDisable && !m_inSampled;
        std::map<AstVar*, AstVar*>& delayedVars = current ? m_delayedDisableVars : m_delayedVars;
        auto it = delayedVars.find(nodep->varp());
        AstVar* outvarp;
        if (it == delayedVars.end()) {
            AstNodeVarRef* const refp = nodep->cloneTree(false);
            refp->user1(true);
            // Sampled, as a derived clock may tick after an update (IEEE 1800-2023 16.9.4)
            AstNodeExpr* valuep = refp;
            if (!current) {
                valuep = new AstSampled{nodep->fileline(), refp, nodep->dtypep(), true};
            }
            outvarp = newDelayedVar((current ? "__VnotfutureDisable" : "__Vnotfuture")
                                        + cvtToStr(m_pastNum) + "_" + nodep->name(),
                                    valuep);
            delayedVars.emplace(nodep->varp(), outvarp);
        } else {
            outvarp = it->second;
        }
        AstVarRef* newp = new AstVarRef{nodep->fileline(), outvarp, VAccess::READ};
        newp->user1(true);
        UINFO(9, "DeFuture " << nodep << "  becomes " << newp);
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstPExpr* nodep) override {
        // V3AssertPre lowered this operator to a forked process, which cannot be evaluated one
        // tick late; the rest of the visit then only strips the future value functions
        nodep->v3warn(E_UNSUPPORTED, "Unsupported: future sampled value function in a property"
                                     " with this temporal operator");
        m_unsupported = true;
        iterateChildren(nodep);
    }
    void visit(AstNodeFTaskRef* nodep) override { unsupported(nodep); }
    void visit(AstMethodCall* nodep) override { unsupported(nodep); }
    void visit(AstNode* nodep) override {
        if (!nodep->isPure()) unsupported(nodep);
        iterateChildren(nodep);
    }

public:
    // CONSTRUCTORS
    explicit AssertDeFutureVisitor(AstNode* nodep, AstNodeModule* modp, unsigned pastNum)
        : m_modp{modp}
        , m_pastNum{pastNum} {
        // See if any Future before we process
        if (nodep->forall([&](const AstFuture* futurep) -> bool {
                m_futurep = futurep;
                return false;
            }))
            return;
        // Only concurrent assertions, which have a PropSpec, are lowered (IEEE 1800-2023 16.9.4)
        AstPropSpec* const specp = VN_AS(nodep, PropSpec);
        // UINFOTREE(9, nodep, "", "defuture-in");
        visit(specp);
        // UINFOTREE(9, nodep, "", "defuture-ou");
        // The attempt checked at a tick is the one from the previous tick, so disable the
        // first tick, which has no previous tick and no delayed values
        FileLine* const flp = specp->fileline();
        AstVar* const startedp = newDelayedVar("__VfutureStarted" + cvtToStr(m_pastNum),
                                               new AstConst{flp, AstConst::BitTrue{}});
        AstNodeExpr* disablep = new AstLogNot{flp, new AstVarRef{flp, startedp, VAccess::READ}};
        if (specp->disablep()) {
            disablep = new AstLogOr{flp, specp->disablep()->unlinkFrBack(), disablep};
        }
        specp->disablep(disablep);
    }
    ~AssertDeFutureVisitor() override = default;
};

// Prepare one default sampled expression.
class DefaultSampledValueVisitor final : public VNVisitor {
    // METHODS
    static AstNodeExpr* newTypeDefault(FileLine* flp, AstNodeDType* dtypep) {
        AstNodeDType* const skipDtp = dtypep->skipRefp();
        if (AstUnpackArrayDType* const arrayp = VN_CAST(skipDtp, UnpackArrayDType)) {
            return new AstConsArray{flp, arrayp, newTypeDefault(flp, arrayp->subDTypep())};
        }
        AstStructDType* const structp = VN_CAST(skipDtp, StructDType);
        if (structp && !structp->packed()) {
            AstConsStruct* const consp = new AstConsStruct{flp, structp};
            for (AstMemberDType* memberp = structp->membersp(); memberp;
                 memberp = VN_AS(memberp->nextp(), MemberDType)) {
                consp->addItemsp(new AstConsStructItem{flp, memberp,
                                                       newTypeDefault(flp, memberp->subDTypep())});
            }
            return consp;
        }
        AstConst* const constp = new AstConst{flp, AstConst::DTyped{}, dtypep};
        if (dtypep->isFourstate()) constp->num().setAllBitsX();
        constp->dtypep(dtypep);
        return constp;
    }
    static bool hasDefaultValue(const AstVar* varp) {
        return !varp->isParam()
               && (varp->isNet() || !varp->lifetime().isStatic() || !varp->hasUserInit());
    }
    static AstNodeExpr* selectFromp(AstNode* nodep) {
        if (AstNodeSel* const selp = VN_CAST(nodep, NodeSel)) return selp->fromp();
        if (AstSel* const selp = VN_CAST(nodep, Sel)) return selp->fromp();
        if (AstStructSel* const selp = VN_CAST(nodep, StructSel)) return selp->fromp();
        return nullptr;
    }
    void visitSelect(AstNodeExpr* nodep) {
        // A selection from a variable with its default value, or with an unknown index, has
        // the default value of the selected type (IEEE 1800-2023 7.4.6, 11.5.1). Replace the
        // whole selection: the variable may be unpacked, and a constant unknown index would
        // be rejected later.
        AstNodeExpr* basep = selectFromp(nodep);
        while (AstNodeExpr* const fromp = selectFromp(basep)) basep = fromp;
        const AstNodeVarRef* const refp = VN_CAST(basep, NodeVarRef);
        bool isDefault = refp && hasDefaultValue(refp->varp());
        if (!isDefault) {
            AstNodeExpr* selp = nodep;
            for (; selectFromp(selp); selp = selectFromp(selp)) {
                // The index of an AstNodeSel or AstSel; an AstStructSel has none
                AstNodeBiop* const biopp = VN_CAST(selp, NodeBiop);
                if (!biopp) continue;
                iterate(biopp->rhsp());
                const AstConst* const constp
                    = VN_CAST(V3Const::constifyEdit(biopp->rhsp()), Const);
                if (constp && constp->num().isAnyXZ()) isDefault = true;
            }
            iterate(selp);
        }
        if (isDefault) {
            nodep->replaceWith(newTypeDefault(nodep->fileline(), nodep->dtypep()));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        }
    }

    // VISITORS
    void visit(AstCMethodHard* nodep) override {
        if (nodep->method() == VCMethod::EVENT_IS_TRIGGERED) {
            nodep->replaceWith(new AstConst{nodep->fileline(), AstConst::BitFalse{}});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
        } else {
            iterateChildren(nodep);
        }
    }
    void visit(AstNodeSel* nodep) override { visitSelect(nodep); }
    void visit(AstSel* nodep) override { visitSelect(nodep); }
    void visit(AstStructSel* nodep) override { visitSelect(nodep); }
    void visit(AstNodeVarRef* nodep) override {
        AstVar* const varp = nodep->varp();
        if (!hasDefaultValue(varp)) {
            // The value of its declaration initializer, not of a later write during
            // initialization (IEEE 1800-2023 16.5.1). V3LinkParse placed that initialization
            // just after a module variable. A connected input does not have the value of its
            // default. With X or Z, the value assigned depends on the X options. Otherwise the
            // variable is read when used, so may have a later value.
            if (varp->isParam() || varp->isNonOutput()) return;
            AstInitialStatic* const initp = VN_CAST(varp->nextp(), InitialStatic);
            if (!initp) return;
            AstAssign* const assignp = VN_AS(initp->stmtsp(), Assign);
            AstConst* const constp = VN_CAST(assignp->rhsp(), Const);
            if (!constp || constp->num().isAnyXZ()) return;
            UASSERT_OBJ(VN_AS(assignp->lhsp(), VarRef)->varp() == varp, nodep,
                        "Initialization of another variable");
            AstConst* const newp = constp->cloneTree(false);
            newp->dtypeFrom(nodep);
            nodep->replaceWith(newp);
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        nodep->replaceWith(newTypeDefault(nodep->fileline(), nodep->dtypep()));
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit DefaultSampledValueVisitor(AstNode* nodep) { iterate(nodep); }
};

//######################################################################
// AssertVisitor

class AssertVisitor final : public VNVisitor {
    // CONSTANTS
    static constexpr uint8_t ALL_ASSERT_TYPES
        = std::numeric_limits<std::underlying_type<VAssertType::en>::type>::max();

    // NODE STATE/TYPES
    // Cleared on netlist
    //  AstNode::user1()         -> bool.  True if processed
    //  AstAlways::user2p()      -> std::vector<AstVar*>. Delayed variables via 'm_delayed'
    //  AstNodeVarRef::user2()   -> bool.  True if shouldn't be sampled
    //  AstIf::user2()           -> bool.  True for assertOn() checks inserted in this pass
    //  AstNodeStmt::user3()     -> bool.  True for a wait of a PExpr attempt (abortWhenKilled)
    const VNUser1InUse m_user1InUse;
    const VNUser2InUse m_user2InUse;
    const VNUser3InUse m_user3InUse;
    VNUser2Allocator<AstAlways, std::vector<AstVar*>> m_delayed;

    // STATE
    AstNodeModule* m_modp = nullptr;  // Last module
    const AstNode* m_beginp = nullptr;  // Last AstBegin/AstGenBlock
    unsigned m_monitorNum = 0;  // Global $monitor numbering (not per module)
    AstVar* m_monitorNumVarp = nullptr;  // $monitor number variable
    AstVar* m_monitorOffVarp = nullptr;  // $monitoroff variable
    AstVar* m_monitorPendingVarp = nullptr;  // $monitor display pending variable
    unsigned m_modPastNum = 0;  // Module past numbering
    unsigned m_modStrobeNum = 0;  // Module $strobe numbering
    AstNodeStmt* m_obsFlushp = nullptr;  // Clears the current process's pending deferred calls
    AstVar* m_obsDoneVarp = nullptr;  // Set when the outermost scope ends without a disable
    std::vector<AstNode*> m_obsWaitsp;  // Current process waits, flushed if it has pending calls
    bool m_inSpawnedFork = false;  // Under a fork...join_any or fork...join_none
    bool m_inForkBranch = false;  // In a fork branch, a process other than the procedure's
    bool m_inConcurrentAction = false;  // In an action of a concurrent assertion
    bool m_inlineAction = false;  // An action of the current assertion stays inline
    AstVar* m_matureEpochp = nullptr;  // Flushes of the current procedure's pending instances
    std::unordered_set<const AstVar*> m_pastVarps;  // Registers of sampled value functions
    AstVar* m_obsEventp = nullptr;  // Current module event to run deferred calls
    AstAlwaysReactive* m_obsReactivep = nullptr;  // Current module block running deferred calls
    AstVar* m_actionEventp = nullptr;  // Current process's event to run queued PExpr actions
    AstAlwaysReactive* m_actionReactivep = nullptr;  // Block running them, beside the process
    std::vector<const AstBegin*> m_namedBeginps;  // Named blocks in the current process
    bool m_inPExprFinal = false;  // In the end-of-simulation check of a PExpr
    AstBegin* m_pexprBodyp = nullptr;  // Body of the current PExpr, its attempt's process
    AstVar* m_strongPassOnp = nullptr;  // Strong property's active attempts started PassOn
    AstVar* m_strongFailOnp = nullptr;  // Strong property's active attempts started FailOn
    std::unordered_map<std::string, AstVar*> m_pexprStartVarps;  // Controls read at its start
    AstNodeProcedure* m_procedurep = nullptr;  // Current procedure
    AstAlways* m_assertCoverp = nullptr;  // Process of the current concurrent assertion
    VDouble0 m_statCover;  // Statistic tracking
    VDouble0 m_statAsNotImm;  // Statistic tracking
    VDouble0 m_statAsImm;  // Statistic tracking
    VDouble0 m_statAsFull;  // Statistic tracking
    VDouble0 m_statPastVars;  // Statistic tracking
    VDouble0 m_statAssertOnCombined;  // Statistic tracking
    VDouble0 m_statAssertOnHoisted;  // Statistic tracking
    bool m_inSampled = false;  // True inside a sampled expression
    bool m_inRestrict = false;  // True inside restrict assertion
    AstNodeStmt* m_passsp = nullptr;  // Current pass statement
    AstNodeStmt* m_failsp = nullptr;  // Current fail statement
    // Pristine action clones for clauses that share the current assertion's action.
    std::unordered_map<const AstPExprClause*, AstNodeStmt*> m_clauseActionsp;
    AstNodeCoverOrAssert* m_assertp = nullptr;  // Current assertion
    AstFinal* m_finalp = nullptr;  // Current final block
    int m_controlTempNum = 0;  // Assertion-control operand temporaries within a module
    VDouble0 m_statLiftedCaseExprs;  // Count of purified case expressions
    AstNodeFTask* m_ftaskp = nullptr;  // Current function/task
    V3UniqueNames m_caseTempNames{"__VCase"};  // Unique names for case temporaries
    V3UniqueNames m_matchCountNames{"__VnfaRemainingMatchCount"};  // Match replay counter names
    V3UniqueNames m_obsNames{"__VassertObs"};  // Observed deferred assertion temp names
    V3UniqueNames m_actionNames{"__VassertAction"};  // Queued and cloned action temporaries
    // Key equality for the delayed value maps. AstNode::sameTree is not enough, as
    // AstVar::sameNode compares only names, and before V3Begin distinct variables in
    // different scopes (e.g. generate blocks) can have the same name.
    struct SameTreeAndVars final {
        static std::vector<const AstVar*> varps(const AstNode& node) {
            std::vector<const AstVar*> varps;
            node.foreach([&](const AstVarRef* refp) { varps.push_back(refp->varp()); });
            return varps;
        }
        template <typename T_Node>
        bool operator()(VNRef<T_Node> ar, VNRef<T_Node> br) const {
            return ar.get().sameTree(&br.get()) && varps(ar.get()) == varps(br.get());
        }
    };
    template <typename T_Node, typename T_Value>
    using SameTreeAndVarsMap
        = std::unordered_map<VNRef<T_Node>, T_Value, std::hash<VNRef<T_Node>>, SameTreeAndVars>;
    // Maps from (expression, senTree) to the AstAlways that computes its delayed values.
    SameTreeAndVarsMap<AstNodeExpr, SameTreeAndVarsMap<AstSenTree, AstAlways*>>
        m_modExpr2Sen2DelayedAlwaysp;
    // Source sampled-value history is initialized, unlike internal property-lowering history.
    SameTreeAndVarsMap<AstNodeExpr, SameTreeAndVarsMap<AstSenTree, AstAlways*>>
        m_modExpr2Sen2DefaultDelayedAlwaysp;
    // Map from delayed-value AstAlways to its last-sampling-tick time variable
    std::unordered_map<const AstAlways*, AstVar*> m_delayedAlways2TickTimep;

    // METHODS
    static const char* assertPassOnQuery(bool vacuous) {
        static constexpr const char* queries[2]
            = {"ASSERT_CTL_PASS_ON_NONVACUOUS", "ASSERT_CTL_PASS_ON_VACUOUS"};
        return queries[vacuous];
    }
    static AstNodeExpr* assertOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                     VAssertDirectiveType directiveType) {
        // cppcheck-suppress missingReturn
        switch (directiveType) {
        case VAssertDirectiveType::INTRINSIC: return new AstConst{fl, AstConst::BitTrue{}};
        case VAssertDirectiveType::VIOLATION_CASE:
        case VAssertDirectiveType::VIOLATION_IF: {
            const bool enabled = directiveType == VAssertDirectiveType::VIOLATION_CASE
                                     ? v3Global.opt.assertCase()
                                     : v3Global.opt.assertOn();
            // If assertions are off, have constant propagation rip them out later
            // This allows syntax errors and such to be detected normally.
            if (!enabled) return new AstConst{fl, AstConst::BitFalse{}};
            // Unique/unique0/priority checks are controlled by their assertion type
            // (IEEE 1800-2023 Table 20-6), as assert directives; full_case/parallel_case
            // checks have no type and follow the global state.
            if (type != VAssertType::INTERNAL) {
                return V3AssertCommon::newAssertCtlGetp(fl, "ASSERT_CTL_ON", type,
                                                        VAssertDirectiveType::ASSERT, statep);
            }
            return new AstCExpr{fl, AstCExpr::Pure{}, "vlSymsp->_vm_contextp__->assertOn()", 1};
        }
        case VAssertDirectiveType::ASSERT:
        case VAssertDirectiveType::COVER:
        case VAssertDirectiveType::ASSUME: {
            if (v3Global.opt.assertOn()) {
                return V3AssertCommon::newAssertCtlGetp(fl, "ASSERT_CTL_ON", type, directiveType,
                                                        statep);
            }
            return new AstConst{fl, AstConst::BitFalse{}};
        }
        case VAssertDirectiveType::INTERNAL:
        case VAssertDirectiveType::RESTRICT: {
            if (v3Global.opt.assertOn()) {
                return new AstCExpr{fl, AstCExpr::Pure{}, "vlSymsp->_vm_contextp__->assertOn()",
                                    1};
            }
            return new AstConst{fl, AstConst::BitFalse{}};
        }
        }
        VL_UNREACHABLE;
    }

    static bool isControlled(VAssertDirectiveType directiveType) {
        return (static_cast<int>(directiveType)
                & (static_cast<int>(VAssertDirectiveType::ASSERT)
                   | static_cast<int>(VAssertDirectiveType::COVER)
                   | static_cast<int>(VAssertDirectiveType::ASSUME)));
    }
    static AstNodeExpr* assertPassOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                         VAssertDirectiveType directiveType, bool vacuous) {
        if (!isControlled(directiveType)) return new AstConst{fl, AstConst::BitTrue{}};
        if (!v3Global.opt.assertOn()) return new AstConst{fl, AstConst::BitFalse{}};
        return V3AssertCommon::newAssertCtlGetp(fl, assertPassOnQuery(vacuous), type,
                                                directiveType, statep);
    }
    static AstNodeExpr* assertFailOnCond(AstVar* statep, FileLine* fl, VAssertType type,
                                         VAssertDirectiveType directiveType) {
        if (!isControlled(directiveType)) return new AstConst{fl, AstConst::BitTrue{}};
        if (!v3Global.opt.assertOn()) return new AstConst{fl, AstConst::BitFalse{}};
        return V3AssertCommon::newAssertCtlGetp(fl, "ASSERT_CTL_FAIL_ON", type, directiveType,
                                                statep);
    }
    string assertDisplayMessage(const AstNode* nodep, const string& prefix, const string& message,
                                VDisplayType severity) {
        if (severity == VDisplayType::DT_ERROR || severity == VDisplayType::DT_FATAL) {
            return ("[%0t] "s + prefix + ": " + nodep->fileline()->filebasename() + ":"
                    + cvtToStr(nodep->fileline()->lineno()) + ": Assertion failed in %m"
                    + ((message != "") ? ": " : "") + message + "\n");
        }
        return ("[%0t] "s + prefix + ": " + nodep->fileline()->filebasename() + ":"
                + cvtToStr(nodep->fileline()->lineno()) + ": %m" + ((message != "") ? ": " : "")
                + message + "\n");
    }
    void replaceDisplay(AstDisplay* nodep, const string& prefix) {
        nodep->fmtp()->text(
            assertDisplayMessage(nodep, prefix, nodep->fmtp()->text(), nodep->displayType()));
        nodep->displayType(VDisplayType::DT_WRITE);
        // cppcheck-suppress nullPointer
        AstNodeExpr* const timenewp = new AstTime{nodep->fileline(), m_modp->timeunit()};
        nodep->fmtp()->prependExprsp(timenewp);
        if (!nodep->fmtp()->scopeNamep() && nodep->fmtp()->formatScopeTracking()) {
            nodep->fmtp()->scopeNamep(new AstScopeName{nodep->fileline(), true});
        }
    }
    AstSampled* newSampledExpr(AstNodeExpr* nodep) {
        return new AstSampled{nodep->fileline(), nodep, nodep->dtypep(), true};
    }
    AstVarRef* newMonitorNumVarRefp(const AstNode* nodep, VAccess access) {
        if (!m_monitorNumVarp) {
            m_monitorNumVarp = new AstVar{nodep->fileline(), VVarType::MODULETEMP, "__VmonitorNum",
                                          nodep->findUInt64DType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorNumVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{nodep->fileline(), m_monitorNumVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstVarRef* newMonitorOffVarRefp(const AstNode* nodep, VAccess access) {
        if (!m_monitorOffVarp) {
            m_monitorOffVarp = new AstVar{nodep->fileline(), VVarType::MODULETEMP, "__VmonitorOff",
                                          nodep->findBitDType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorOffVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{nodep->fileline(), m_monitorOffVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstVarRef* newMonitorPendingVarRefp(const AstNode* nodep, VAccess access) {
        FileLine* const flp = nodep->fileline();
        if (!m_monitorPendingVarp) {
            m_monitorPendingVarp = new AstVar{flp, VVarType::MODULETEMP, "__VmonitorPending",
                                              nodep->findBitDType()};
            v3Global.rootp()->dollarUnitPkgp()->addStmtsp(m_monitorPendingVarp);
        }
        AstVarRef* const varrefp = new AstVarRef{flp, m_monitorPendingVarp, access};
        varrefp->classOrPackagep(v3Global.rootp()->dollarUnitPkgp());
        return varrefp;
    }
    AstAssign* newMonitorPendingSetp(const AstNode* nodep) {
        FileLine* const flp = nodep->fileline();
        return new AstAssign{flp, newMonitorPendingVarRefp(nodep, VAccess::WRITE),
                             new AstConst{flp, AstConst::BitTrue{}}};
    }
    static AstVar* newModuleTemp(FileLine* flp, const string& name, AstNodeDType* dtypep,
                                 AstNodeModule* ownerp) {
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, dtypep};
        varp->isInternal(true);
        ownerp->addStmtsp(varp);
        return varp;
    }
    AstNodeStmt* newDeferredAssertFlush(FileLine* flp) const {
        return new AstDeferredAssertFlush{flp, m_obsFlushp->cloneTree(true)};
    }
    // Add the flushes of a process once it is known to have observed deferred assertions
    template <typename T_Scope>
    void addObsFlushes(T_Scope* scopep) {
        if (!m_obsFlushp) return;
        for (AstNode* const nodep : m_obsWaitsp) {
            if (AstEventControl* const controlp = VN_CAST(nodep, EventControl)) {
                addResumeFlush(controlp);
            } else if (AstWait* const waitp = VN_CAST(nodep, Wait)) {
                addResumeFlush(waitp);
            } else {  // AstWaitFork has no statements
                nodep->addNextHere(newDeferredAssertFlush(nodep->fileline()));
            }
        }
        // IEEE 1800-2023 16.4.4: Flush when the outermost scope was exited by a disable
        if (m_obsDoneVarp) {
            FileLine* const flp = scopep->fileline();
            // Clear for the next run of an always
            AstAssign* const clearp
                = new AstAssign{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::WRITE},
                                new AstConst{flp, AstConst::BitFalse{}}};
            scopep->addStmtsp(new AstIf{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::READ},
                                        clearp, newDeferredAssertFlush(flp)});
        }
        VL_DO_DANGLING(m_obsFlushp->deleteTree(), m_obsFlushp);
    }
    template <typename T_HasStmtsp>
    void addResumeFlush(T_HasStmtsp* nodep) const {
        if (!m_obsFlushp) return;
        if (nodep->stmtsp()) {
            nodep->stmtsp()->addHereThisAsNext(newDeferredAssertFlush(nodep->fileline()));
        } else {
            nodep->addStmtsp(newDeferredAssertFlush(nodep->fileline()));
        }
    }
    static AstQueueDType* newQueueDTypep(FileLine* flp, AstNodeDType* elemDTypep) {
        AstQueueDType* const queueDtp = new AstQueueDType{flp, elemDTypep, nullptr};
        v3Global.rootp()->typeTablep()->addTypesp(queueDtp);
        return queueDtp;
    }
    static AstNodeStmt* newQueuePush(FileLine* flp, AstVar* queuep, AstNodeExpr* valuep) {
        AstCMethodHard* const callp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::WRITE}, VCMethod::ARRAY_PUSH_BACK, valuep};
        callp->dtypeSetVoid();
        return callp->makeStmt();
    }
    static AstCMethodHard* newQueuePop(FileLine* flp, AstVar* queuep, AstNodeDType* elemDTypep) {
        AstCMethodHard* const callp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::READWRITE}, VCMethod::ARRAY_POP_FRONT};
        callp->dtypeFrom(elemDTypep);
        return callp;
    }
    struct DeferredReportQueues final {
        AstNodeStmt* enqueuep = nullptr;
        AstNodeStmt* maturep = nullptr;
        AstNodeStmt* discardp = nullptr;
        const AstNodeCoverOrAssert* assertp;
    };
    void snapshotObservedExpr(AstNodeExpr* exprp, DeferredReportQueues& queues) {
        // Constants and, within the time step of the call, the time cannot change
        if (VN_IS(exprp, Const) || VN_IS(exprp, Time)) return;
        FileLine* const flp = exprp->fileline();
        AstNodeDType* const dtypep = exprp->dtypep();
        AstVar* const queuep
            = newModuleTemp(flp, m_obsNames.get("ValQueue"), newQueueDTypep(flp, dtypep), m_modp);
        queuep->setIgnoreSchedWrite();
        VNRelinker handle;
        AstNodeExpr* const oldp = exprp->unlinkFrBack(&handle);
        AstVar* const readp
            = newModuleTemp(flp, m_obsNames.get("MatureQueue"), queuep->dtypep(), m_modp);
        readp->setIgnoreSchedWrite();
        queues.maturep = AstNode::addNext(
            queues.maturep, newQueuePush(flp, readp, newQueuePop(flp, queuep, dtypep)));
        queues.discardp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
            queues.discardp, newQueuePop(flp, queuep, dtypep)->makeStmt());
        handle.relink(newQueuePop(flp, readp, dtypep));
        queues.enqueuep = AstNode::addNext(queues.enqueuep, newQueuePush(flp, queuep, oldp));
        AstCMethodHard* const clearp = new AstCMethodHard{
            flp, new AstVarRef{flp, queuep, VAccess::WRITE}, VCMethod::DYN_CLEAR};
        clearp->dtypeSetVoid();
        m_obsFlushp = AstNode::addNext(m_obsFlushp, clearp->makeStmt());
    }
    void snapshotObservedSFormatArgs(AstSFormatF* fmtp, DeferredReportQueues& queues) {
        for (AstNodeExpr* const exprp : fmtp->exprspList()) {
            AstSFormatArg* const argp = VN_CAST(exprp, SFormatArg);
            snapshotObservedExpr(argp ? argp->exprp() : exprp, queues);
        }
    }
    static AstIf* newIfAssertOn(AstVar* statep, AstNodeStmt* bodyp,
                                VAssertDirectiveType directiveType,
                                VAssertType type = VAssertType::INTERNAL) {
        // Add an internal if to check assertions are on.
        // Don't make this an AND term, as it's unlikely to need to test this.
        FileLine* const fl = bodyp->fileline();

        AstNodeExpr* const condp = assertOnCond(statep, fl, type, directiveType);
        AstIf* const newp = new AstIf{fl, condp, bodyp};
        newp->isBoundsCheck(true);  // To avoid LATCH warning
        newp->user2(true);  // Mark as an assertOn() check
        return newp;
    }
    // Gate 'bodyp' by 'condp' as an assertion control check
    static AstIf* newIfControl(AstNodeExpr* condp, AstNodeStmt* bodyp) {
        AstIf* const newp = new AstIf{condp->fileline(), condp, bodyp};
        newp->isBoundsCheck(true);  // To avoid LATCH warning
        newp->user1(true);  // Don't assert/cover this if
        newp->user2(true);  // Mark as an assertOn() check
        return newp;
    }
    static AstNodeStmt* newIfAssertPassOn(AstVar* statep, AstNodeStmt* bodyp,
                                          VAssertDirectiveType directiveType, VAssertType type,
                                          bool vacuous) {
        // Add an internal if to check assertion passOn is enabled.
        // Don't make this an AND term, as it's unlikely to need to test this.
        return newIfControl(
            assertPassOnCond(statep, bodyp->fileline(), type, directiveType, vacuous), bodyp);
    }
    static AstNodeStmt* newIfAssertFailOn(AstVar* statep, AstNodeStmt* bodyp,
                                          VAssertDirectiveType directiveType, VAssertType type) {
        // Add an internal if to check assertion failOn is enabled.
        // Don't make this an AND term, as it's unlikely to need to test this.
        return newIfControl(assertFailOnCond(statep, bodyp->fileline(), type, directiveType),
                            bodyp);
    }

    static AstIf* assertCond(const AstNodeCoverOrAssert* nodep, AstNodeExpr* propp,
                             AstNodeStmt* passsp, AstNodeStmt* failsp) {
        AstIf* const ifp = new AstIf{nodep->fileline(), propp, passsp, failsp};
        // It's more LIKELY that we'll take the nullptr if clause
        // than the sim-killing else clause:
        ifp->branchPred(VBranchPred::BP_LIKELY);
        ifp->isBoundsCheck(true);  // To avoid LATCH warning
        return ifp;
    }

    AstNodeStmt* assertBody(const AstNodeCoverOrAssert* nodep, AstNode* propp, AstNodeStmt* passsp,
                            AstNodeStmt* failsp) {
        if (AstPExpr* const pexprp = VN_CAST(propp, PExpr)) {
            if (!v3Global.opt.timing().isSetTrue()) {
                nodep->v3warn(E_NOTIMING, "This property expression requires --timing");
                VL_DO_DANGLING(pushDeletep(pexprp), pexprp);
                return new AstBegin{nodep->fileline(), "", nullptr, false};
            }
            AstFork* const forkp = new AstFork{nodep->fileline(), VJoinType::JOIN_NONE};
            forkp->addForksp(new AstForkItem{nodep->fileline(), pexprp->bodyp()->unlinkFrBack()});
            if (AstNodeStmt* const finalp = pexprp->finalp()) {
                // The end-of-simulation check runs action blocks in a final block, where an
                // NBA, legal in an action block, executes as a blocking assignment
                finalp->foreach([](AstAssignDly* const dlyp) {
                    FileLine* const newfl = new FileLine{dlyp->fileline()};
                    newfl->warnOff(V3ErrorCode::FINALDLY, true);
                    dlyp->fileline(newfl);
                });
                // The final block executes in zero time (IEEE 1800-2023 9.2.3), so a timing
                // control there never resumes
                const AstNode* timingp = nullptr;
                finalp->exists([&](const AstNode* const np) {
                    if (!np->isTimingControl()) return false;
                    timingp = np;
                    return true;
                });
                if (timingp) {
                    timingp->v3warn(E_UNSUPPORTED,
                                    "Unsupported: Timing control in action block of a strong "
                                    "property, which also runs at end of simulation");
                    VL_DO_DANGLING(pushDeletep(finalp->unlinkFrBack()), finalp);
                } else if (!m_finalp) {
                    m_finalp = new AstFinal{m_modp->fileline(), finalp->unlinkFrBack()};
                    m_modp->addStmtsp(m_finalp);
                } else {
                    m_finalp->addStmtsp(finalp->unlinkFrBack());
                }
            }
            VL_DO_DANGLING2(pushDeletep(pexprp), pexprp, propp);
            return forkp;
        }

        return assertCond(nodep, VN_AS(propp, NodeExpr), passsp, failsp);
    }

    AstNodeStmt* newFireAssertUnchecked(const AstNodeStmt* nodep, const string& message,
                                        AstNodeExpr* exprsp = nullptr) {
        // Like newFireAssert() but omits the asserts-on check
        AstDisplay* const dispp
            = new AstDisplay{nodep->fileline(), VDisplayType::DT_ERROR, message, nullptr, nullptr};
        dispp->fmtp()->timeunit(m_modp->timeunit());
        AstNodeStmt* const bodysp = dispp;
        replaceDisplay(dispp, "%%Error");  // Convert to standard DISPLAY format
        if (exprsp) dispp->fmtp()->exprsp()->addNext(exprsp);
        if (v3Global.opt.stopFail()) bodysp->addNext(new AstStop{nodep->fileline(), false});
        return bodysp;
    }

    AstNodeStmt* newFireAssert(const AstNodeStmt* nodep, VAssertDirectiveType directiveType,
                               VAssertType assertType, const string& message,
                               AstNodeExpr* exprsp = nullptr) {
        AstNodeStmt* bodysp = newFireAssertUnchecked(nodep, message, exprsp);
        bodysp = newIfAssertOn(nodep->controlVarp(), bodysp, directiveType, assertType);
        return bodysp;
    }

    AstVar* createDelayedVar(const std::string& name, AstAlways* alwaysp, AstNodeExpr* exprp,
                             AstNodeExpr* initp) {
        FileLine* const flp = exprp->fileline();
        AstVar* const varp = new AstVar{flp, VVarType::MODULETEMP, name, exprp->dtypep()};
        // TODO: this lifetime seems nonsene (can't have NBAs to automatics), but is as before
        varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        m_modp->addStmtsp(varp);
        // Before enough clock ticks, $past returns the expression's default sampled value.
        if (initp) {
            m_modp->addStmtsp(new AstInitialStatic{
                flp, new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE}, initp}});
        }
        ++m_statPastVars;
        m_pastVarps.insert(varp);
        // Actually set the delayed value
        AstNodeExpr* const lhsp = new AstVarRef{flp, varp, VAccess::WRITE};
        AstAssignDly* const assignp = new AstAssignDly{flp, lhsp, exprp};
        alwaysp->prependStmtsp(assignp);
        return varp;
    }

    // The always block computing the delayed values, shared by identical expressions unless
    // 'ownHistory'
    AstAlways* getDelayedAlways(AstNodeExpr* exprp, AstNodeExpr* initp, AstSenTree* senTreep,
                                bool ownHistory) {
        auto& expr2Sen2Alwaysr
            = initp ? m_modExpr2Sen2DefaultDelayedAlwaysp : m_modExpr2Sen2DelayedAlwaysp;
        AstAlways* ownAlwaysp = nullptr;
        AstAlways*& alwayspr = ownHistory ? ownAlwaysp : expr2Sen2Alwaysr[*exprp][*senTreep];
        if (!alwayspr) {
            FileLine* const flp = exprp->fileline();
            // Create the always block that computes the delayed values
            alwayspr = new AstAlways{flp, VAlwaysKwd::ALWAYS, senTreep, nullptr};
            m_modp->addStmtsp(alwayspr);
            // Create the once-delayed variable
            const std::string name = "_Vpast_" + cvtToStr(m_modPastNum++) + "_1";
            AstVar* const varp = createDelayedVar(name, alwayspr, exprp, initp);
            // Add it to delayed variable vector
            m_delayed(alwayspr).emplace_back(varp);
        } else {
            // Reusing exiting, not needed
            VL_DO_DANGLING(pushDeletep(exprp), exprp);
            if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
            VL_DO_DANGLING(pushDeletep(senTreep), senTreep);
        }
        return alwayspr;
    }

    AstNodeExpr* getPastValue(AstNodeExpr* exprp, AstNodeExpr* initp, AstSenTree* senTreep,
                              uint32_t ticks, bool ownHistory) {
        UASSERT_OBJ(ticks > 0, exprp, "Delay must be > 0");
        FileLine* const flp = exprp->fileline();
        AstAlways* const alwaysp = getDelayedAlways(
            exprp, initp ? initp->cloneTreePure(false) : nullptr, senTreep, ownHistory);
        AstNodeExpr* const resultp = pastValueRef(alwaysp, flp, ticks, initp);
        if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
        return resultp;
    }

    AstNodeExpr* pastValueRef(AstAlways* alwaysp, FileLine* flp, uint32_t ticks,
                              AstNodeExpr* initp) {
        std::vector<AstVar*>& delayedr = m_delayed(alwaysp);
        // Ensure the required delay exists
        while (delayedr.size() < ticks) {
            AstVar* const firstp = delayedr.front();
            FileLine* const varFlp = firstp->fileline();
            // Create once more delayed value
            std::string name = firstp->name();
            name.resize(name.size() - 1);
            name += std::to_string(delayedr.size() + 1);
            AstNodeExpr* const prevp = new AstVarRef{varFlp, delayedr.back(), VAccess::READ};
            AstVar* const varp = createDelayedVar(name, alwaysp, prevp,
                                                  initp ? initp->cloneTreePure(false) : nullptr);
            // Add it to delayed variable vector
            delayedr.emplace_back(varp);
        }
        // Return a reference to the appropriately delayed variable
        return new AstVarRef{flp, delayedr.at(ticks - 1), VAccess::READ};
    }

    // Time of the pipeline's last sampling tick, for end-of-simulation readers
    AstVar* getPastTickTimeVar(AstAlways* alwaysp) {
        AstVar*& varpr = m_delayedAlways2TickTimep[alwaysp];
        if (!varpr) {
            FileLine* const flp = alwaysp->fileline();
            varpr = new AstVar{flp, VVarType::MODULETEMP,
                               "_Vpast_" + cvtToStr(m_modPastNum++) + "_t",
                               m_modp->findUInt64DType()};
            m_modp->addStmtsp(varpr);
            AstNodeExpr* const timep = new AstCExpr{flp, "vlSymsp->_vm_contextp__->time()", 64};
            alwaysp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, varpr, VAccess::WRITE}, timep});
        }
        return varpr;
    }

    // Lower observed deferred action into a pending call with its input arguments snapshotted.
    // Pending calls run in the Reactive region unless a flush of their process clears them
    // (IEEE 1800-2023 16.4.1).
    AstNodeStmt* newObservedDeferredAction(FileLine* flp, AstNodeStmt* actionsp,
                                           const AstNodeCoverOrAssert* assertp) {
        // The null statement of an 'else;', an empty implied block, has no call to defer
        const AstBegin* const beginp = VN_CAST(actionsp, Begin);
        if (beginp && beginp->implied() && !beginp->stmtsp()) return actionsp;
        if (!(actionsp->isOutputter() || VN_IS(actionsp, SFormat) || VN_IS(actionsp, StmtExpr))) {
            actionsp->v3error("Observed deferred immediate assertion action block must be a "
                              "single subroutine call (IEEE 1800-2023 16.4).");
            VL_DO_DANGLING(pushDeletep(actionsp), actionsp);
            return nullptr;
        }
        AstStmtExpr* const stmtexprp = VN_CAST(actionsp, StmtExpr);
        AstNodeFTaskRef* const refp
            = stmtexprp ? VN_CAST(stmtexprp->exprp(), NodeFTaskRef) : nullptr;
        if (!(VN_IS(actionsp, Display) || VN_IS(actionsp, SFormat) || VN_IS(actionsp, SystemT)
              || VN_IS(actionsp, Stop) || VN_IS(actionsp, Finish) || refp)) {
            actionsp->v3warn(E_UNSUPPORTED,
                             "Unsupported: Observed deferred immediate assertion action.");
            VL_DO_DANGLING(pushDeletep(actionsp), actionsp);
            return nullptr;
        }
        DeferredReportQueues queues{nullptr, nullptr, nullptr, assertp};
        if (AstDisplay* const displayp = VN_CAST(actionsp, Display)) {
            if (displayp->filep()) snapshotObservedExpr(displayp->filep(), queues);
            snapshotObservedSFormatArgs(displayp->fmtp(), queues);
        } else if (AstSFormat* const sformatp = VN_CAST(actionsp, SFormat)) {
            snapshotObservedSFormatArgs(sformatp->fmtp(), queues);
        } else if (AstSystemT* const systemp = VN_CAST(actionsp, SystemT)) {
            snapshotObservedExpr(systemp->lhsp(), queues);
        } else if (refp) {
            // Match actuals to formal ports, including named/default arguments
            const V3TaskConnects tconnects
                = V3Task::taskConnects(refp, refp->taskp()->declsp(), nullptr, false);
            for (const auto& tconnect : tconnects) {
                AstVar* const portp = tconnect.first;
                AstArg* const argp = tconnect.second;
                if (portp->isRef() || portp->isConstRef()) {
                    if (argp->exprp()->exists([](const AstNodeVarRef* varrefp) {
                            return varrefp->varp()->lifetime().isAutomatic()
                                   || varrefp->varp()->dtypep()->skipRefp()->isDynamicallySized();
                        })) {
                        argp->exprp()->v3error(
                            "Observed deferred immediate assertion ref action argument cannot "
                            "have automatic or dynamic storage (IEEE 1800-2023 16.4).");
                    }
                } else if (portp->isNonOutput()) {
                    snapshotObservedExpr(argp->exprp(), queues);
                } else {
                    argp->exprp()->v3error("Observed deferred immediate assertion action "
                                           "argument must be input, ref, or const ref "
                                           "(IEEE 1800-2023 16.4).");
                }
            }
        }
        return newObservedDeferredCall(flp, actionsp, queues);
    }
    // Make statements pending, appending what queues them to queuesp
    AstNodeStmt* newObservedDeferredCall(FileLine* flp, AstNodeStmt* callsp,
                                         DeferredReportQueues& queues) {
        AstVar* const pendingp
            = newModuleTemp(flp, m_obsNames.get("Pending"), m_modp->findUInt32DType(), m_modp);
        pendingp->setIgnoreSchedWrite();
        m_obsFlushp = AstNode::addNext(
            m_obsFlushp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                       new AstConst{flp, 0}});
        if (!m_obsEventp) {
            m_obsEventp = newModuleTemp(flp, m_obsNames.get("Event"),
                                        m_modp->findBasicDType(VBasicDTypeKwd::EVENT), m_modp);
            v3Global.setHasEvents();
            v3Global.setUsesTiming();
            m_obsReactivep = new AstAlwaysReactive{
                flp,
                new AstSenTree{flp,
                               new AstSenItem{flp, VEdgeType::ET_EVENT,
                                              new AstVarRef{flp, m_obsEventp, VAccess::READ}}},
                nullptr};
            m_obsReactivep->deferredReports(true);
            m_modp->addStmtsp(m_obsReactivep);
        }
        AstVar* const readyp
            = newModuleTemp(flp, m_obsNames.get("Ready"), pendingp->dtypep(), m_modp);
        readyp->setIgnoreSchedWrite();
        AstNodeStmt* queuesp = addObservedReportMaturity(flp, pendingp, readyp, queues);
        queuesp = AstNode::addNext(
            queuesp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                   new AstAdd{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                              new AstConst{flp, 1}}});
        queuesp = AstNode::addNext(
            queuesp,
            new AstFireEvent{flp, new AstVarRef{flp, m_obsEventp, VAccess::WRITE}, false});

        AstLoop* const reactLoopp = new AstLoop{flp};
        reactLoopp->addStmtsp(
            new AstLoopTest{flp, reactLoopp, new AstVarRef{flp, readyp, VAccess::READ}});
        reactLoopp->addStmtsp(new AstAssign{
            flp, new AstVarRef{flp, readyp, VAccess::WRITE},
            new AstSub{flp, new AstVarRef{flp, readyp, VAccess::READ}, new AstConst{flp, 1}}});
        reactLoopp->addStmtsp(callsp);
        m_obsReactivep->addStmtsp(reactLoopp);
        return queuesp;
    }

    // Pending reports can be killed; after Observed maturity they always run in Reactive
    // (IEEE 1800-2023 16.4.1, 20.11). Move or discard each report's arguments together.
    AstNodeStmt* addObservedReportMaturity(FileLine* flp, AstVar* pendingp, AstVar* readyp,
                                          DeferredReportQueues& queues) {
        AstNodeDType* const u32p = pendingp->dtypep();
        AstVar* const killQp
            = newModuleTemp(flp, m_obsNames.get("KillQueue"), newQueueDTypep(flp, u32p), m_modp);
        killQp->setIgnoreSchedWrite();
        AstCMethodHard* const clearp = new AstCMethodHard{
            flp, new AstVarRef{flp, killQp, VAccess::WRITE}, VCMethod::DYN_CLEAR};
        clearp->dtypeSetVoid();
        m_obsFlushp = AstNode::addNext(m_obsFlushp, clearp->makeStmt());
        const auto newInc = [&](AstVar* varp, bool add) {
            AstNodeExpr* const rhsp = new AstVarRef{flp, varp, VAccess::READ};
            AstConst* const onep = new AstConst{flp, 1};
            AstNodeExpr* const valuep
                = add ? static_cast<AstNodeExpr*>(new AstAdd{flp, rhsp, onep})
                      : new AstSub{flp, rhsp, onep};
            return new AstAssign{flp, new AstVarRef{flp, varp, VAccess::WRITE}, valuep};
        };
        AstLoop* const loopp = new AstLoop{flp};
        loopp->addStmtsp(new AstLoopTest{flp, loopp, new AstVarRef{flp, pendingp, VAccess::READ}});
        loopp->addStmtsp(newInc(pendingp, false));
        AstNodeExpr* const keep = new AstEq{flp, newQueuePop(flp, killQp, u32p),
                                           newKillCountp(flp, queues.assertp)};
        loopp->addStmtsp(new AstIf{
            flp, keep, AstNode::addNext(queues.maturep, newInc(readyp, true)), queues.discardp});
        AstSenTree* const senp = new AstSenTree{
            flp, new AstSenItem{flp, VEdgeType::ET_EVENT,
                               new AstVarRef{flp, m_obsEventp, VAccess::READ}}};
        m_modp->addStmtsp(new AstAlwaysObserved{flp, senp, loopp});
        return AstNode::addNext(queues.enqueuep,
                                newQueuePush(flp, killQp, newKillCountp(flp, queues.assertp)));
    }

    // Return the variable holding the value of 'condp' at the start of the current PExpr's
    // attempt, which the assertion controls apply to (IEEE 1800-2023 20.11)
    AstVar* getPExprStartVarp(const std::string& key, AstNodeExpr* condp) {
        AstVar*& varpr = m_pexprStartVarps[key];
        if (varpr) {
            VL_DO_DANGLING(pushDeletep(condp), condp);
            return varpr;
        }
        FileLine* const flp = condp->fileline();
        varpr = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Start"), condp->dtypep()};
        varpr->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
        m_pexprBodyp->addDeclsp(varpr);
        AstAssign* const initp
            = new AstAssign{flp, new AstVarRef{flp, varpr, VAccess::WRITE}, condp};
        // Every PExpr body V3AssertPre creates has statements other than clauses (see the census
        // in the PExpr lowerings), which stay while V3Assert visits it
        AstNode* const stmtsp = m_pexprBodyp->stmtsp();
        UASSERT_OBJ(stmtsp, m_pexprBodyp, "Empty PExpr body");
        stmtsp->addHereThisAsNext(initp);
        return varpr;
    }
    // The Kill count of the current assertion
    static AstNodeExpr* newKillCountp(FileLine* flp, const AstNodeCoverOrAssert* assertp) {
        return V3AssertCommon::newAssertCtlGetp(flp, "ASSERT_CTL_KILL", assertp->userType(),
                                                assertp->directive(), assertp->controlVarp());
    }
    AstNodeExpr* newKillCountp(FileLine* flp) const { return newKillCountp(flp, m_assertp); }
    // A Kill aborts an executing attempt (IEEE 1800-2023 20.11): after each wait of the attempt
    // of 'nodep' (marked by user3), end it if killed since its start, so it evaluates nothing
    // further.
    void abortWhenKilled(AstPExpr* nodep) {
        AstBegin* const bodyp = nodep->bodyp();
        FileLine* const flp = bodyp->fileline();
        AstVar* const killp = getPExprStartVarp("kill", newKillCountp(flp));
        AstNodeStmt* const stmtsp = bodyp->stmtsp();
        UASSERT_OBJ(stmtsp, bodyp, "Empty PExpr body");
        AstJumpBlock* const blockp = new AstJumpBlock{flp, stmtsp->unlinkFrBackWithNext()};
        bodyp->addStmtsp(blockp);
        std::vector<AstNodeStmt*> waitps;
        blockp->foreach([&](AstNodeStmt* stmtp) {
            if (stmtp->user3()) waitps.push_back(stmtp);
            stmtp->user3(false);  // Not for an enclosing PExpr
        });
        for (AstNodeStmt* const waitp : waitps) {
            waitp->addNextHere(new AstIf{
                flp, new AstNeq{flp, new AstVarRef{flp, killp, VAccess::READ}, newKillCountp(flp)},
                new AstJumpGo{flp, blockp}});
        }
        if (nodep->finalp()) dropKilledAtFinal(nodep);
    }
    // The end-of-simulation check of a strong property checks the attempts V3AssertPre records
    // as active, in an associative array by process, or a count, which the check reads first.
    // The attempts executing at a Kill are aborted (IEEE 1800-2023 20.11), and aborted attempts
    // do not retire themselves, so once the Kill count differs from that of the attempts
    // recorded, they are all dropped, at the start of the next attempt or of the check.
    void dropKilledAtFinal(AstPExpr* nodep) {
        AstBegin* const finalp = VN_AS(nodep->finalp(), Begin);
        FileLine* const flp = finalp->fileline();
        const AstAssign* const countp = VN_CAST(finalp->stmtsp(), Assign);
        UASSERT_OBJ(countp, finalp, "Expected the count of the active attempts first");
        AstNodeStmt* clearp = nullptr;
        AstVar* activep = nullptr;
        if (const AstCMethodHard* const sizep = VN_CAST(countp->rhsp(), CMethodHard)) {
            UASSERT_OBJ(sizep->method() == VCMethod::ASSOC_SIZE, sizep, "Expected a size");
            activep = VN_AS(sizep->fromp(), VarRef)->varp();
            AstCMethodHard* const callp = new AstCMethodHard{
                flp, new AstVarRef{flp, activep, VAccess::WRITE}, VCMethod::ASSOC_CLEAR};
            callp->dtypeSetVoid();
            clearp = callp->makeStmt();
        } else {
            activep = VN_AS(countp->rhsp(), VarRef)->varp();
            clearp
                = new AstAssign{flp, new AstVarRef{flp, activep, VAccess::WRITE},
                                new AstConst{flp, AstConst::WidthedValue{}, activep->width(), 0}};
        }
        AstVar* const epochp
            = newModuleTemp(flp, m_actionNames.get("Epoch"), m_modp->findUInt32DType(), m_modp);
        epochp->lifetime(VLifetime::STATIC_EXPLICIT);
        const auto newDropIfp = [&](bool update) {
            AstIf* const ifp = new AstIf{
                flp,
                new AstNeq{flp, new AstVarRef{flp, epochp, VAccess::READ}, newKillCountp(flp)},
                clearp->cloneTree(false)};
            for (AstVar* const countp : {m_strongPassOnp, m_strongFailOnp}) {
                ifp->addThensp(new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE},
                                             new AstConst{flp, AstConst::WidthedValue{}, 32, 0}});
            }
            if (update) {
                ifp->addThensp(new AstAssign{flp, new AstVarRef{flp, epochp, VAccess::WRITE},
                                             newKillCountp(flp)});
            }
            return ifp;
        };
        AstNodeStmt* const blockp = nodep->bodyp()->stmtsp();
        blockp->addHereThisAsNext(newDropIfp(true));
        finalp->stmtsp()->addHereThisAsNext(newDropIfp(false));
        // Count the recorded attempts by the controls at their start, where V3AssertPre records
        // and retires them
        const VAssertDirectiveType directive = m_assertp->directive();
        const VAssertType type = m_assertp->userType();
        AstVar* const passStartp = getPExprStartVarp(
            "pass0", assertPassOnCond(m_assertp->controlVarp(), flp, type, directive, false));
        AstVar* const failStartp = getPExprStartVarp(
            "fail", assertFailOnCond(m_assertp->controlVarp(), flp, type, directive));
        const auto newCountp = [&](bool inc) {
            AstNodeStmt* stmtsp = nullptr;
            for (AstVar* const countp : {m_strongPassOnp, m_strongFailOnp}) {
                AstNodeExpr* const onep = new AstConst{flp, AstConst::WidthedValue{}, 32, 1};
                AstNodeExpr* const valuep
                    = inc ? static_cast<AstNodeExpr*>(
                                new AstAdd{flp, new AstVarRef{flp, countp, VAccess::READ}, onep})
                          : new AstSub{flp, new AstVarRef{flp, countp, VAccess::READ}, onep};
                stmtsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                    stmtsp,
                    new AstIf{
                        flp,
                        new AstVarRef{flp, countp == m_strongPassOnp ? passStartp : failStartp,
                                      VAccess::READ},
                        new AstAssign{flp, new AstVarRef{flp, countp, VAccess::WRITE}, valuep}});
            }
            return stmtsp;
        };
        std::vector<AstNodeStmt*> recordps;
        std::vector<AstNodeStmt*> retireps;
        blockp->foreach([&](AstNodeStmt* stmtp) {
            if (const AstAssign* const assignp = VN_CAST(stmtp, Assign)) {
                const AstAssocSel* const selp = VN_CAST(assignp->lhsp(), AssocSel);
                const AstVarRef* const refp
                    = VN_CAST(selp ? selp->fromp() : assignp->lhsp(), VarRef);
                if (!refp || refp->varp() != activep) return;
                if (selp || VN_IS(assignp->rhsp(), Add)) recordps.push_back(stmtp);
                if (VN_IS(assignp->rhsp(), Sub)) retireps.push_back(stmtp);
            } else if (const AstStmtExpr* const exprp = VN_CAST(stmtp, StmtExpr)) {
                const AstCMethodHard* const methodp = VN_CAST(exprp->exprp(), CMethodHard);
                if (methodp && methodp->method() == VCMethod::ASSOC_ERASE
                    && VN_AS(methodp->fromp(), VarRef)->varp() == activep) {
                    retireps.push_back(stmtp);
                }
            }
        });
        UASSERT_OBJ(!recordps.empty(), nodep, "Expected the record of a strong attempt");
        for (AstNodeStmt* const stmtp : recordps) stmtp->addNextHere(newCountp(true));
        for (AstNodeStmt* const stmtp : retireps) stmtp->addNextHere(newCountp(false));
        VL_DO_DANGLING(pushDeletep(clearp), clearp);
    }
    // Whether an action is left where it is, rather than queued (see newQueuedAction)
    static bool actionStaysInline(AstNodeStmt* actionsp) {
        std::unordered_set<const AstVar*> ownps;  // What the action declares
        actionsp->foreachAndNext([&](const AstVar* varp) { ownps.insert(varp); });
        // Automatic inputs of an action shall not be modified (IEEE 1800-2023 16.14.6.1), leave
        // such an action where V3Fork reports it
        if (actionsp->existsAndNext([&](const AstVarRef* refp) {
                return refp->access().isWriteOrRW() && refp->varp()->lifetime().isAutomatic()
                       && !ownps.count(refp->varp());
            })) {
            return true;
        }
        // Also leave an action jumping out of itself, e.g. disabling a block of the process
        std::unordered_set<const AstJumpBlock*> blockps;  // What the action contains
        actionsp->foreachAndNext([&](const AstJumpBlock* blockp) { blockps.insert(blockp); });
        return actionsp->existsAndNext([&](const AstNode* np) {
            const AstJumpGo* const gop = VN_CAST(np, JumpGo);
            return VN_IS(np, Disable) || (gop && !blockps.count(gop->blockp()));
        });
    }
    // Queue the action of a PExpr clause, run in the Reactive region (IEEE 1800-2023 4.4.2.6).
    // Return what queues it, at the decision of the attempt. An entry of the queue holds the
    // values of the automatic variables it reads (IEEE 1800-2023 16.14.6.1).
    AstNodeStmt* newQueuedAction(FileLine* flp, AstNodeStmt* actionsp) {
        // Without timing, assertBody rejects the PExpr
        if (!v3Global.opt.timing().isSetTrue()) return actionsp;
        // A sequence event control resumes its waiters from the cover action, and without
        // coverage the cover statement is deleted
        const AstCover* const coverp = VN_CAST(m_assertp, Cover);
        if (coverp && (coverp->isSeqEvent() || !v3Global.opt.coverageUser())) return actionsp;
        if (actionStaysInline(actionsp)) {
            m_inlineAction = true;
            return actionsp;
        }
        std::unordered_set<const AstVar*> ownps;  // What the action declares
        actionsp->foreachAndNext([&](const AstVar* varp) { ownps.insert(varp); });
        // Queued from the process of the attempt, a fork of the process of the assertion
        const auto newTemp = [&](const string& name, AstNodeDType* dtypep) {
            AstVar* const varp = newModuleTemp(flp, m_actionNames.get(name), dtypep, m_modp);
            varp->lifetime(VLifetime::STATIC_EXPLICIT);
            return varp;
        };
        if (!m_actionEventp) {
            m_actionEventp = newTemp("Event", m_modp->findBasicDType(VBasicDTypeKwd::EVENT));
            v3Global.setHasEvents();
            m_actionReactivep = new AstAlwaysReactive{
                flp,
                new AstSenTree{flp,
                               new AstSenItem{flp, VEdgeType::ET_EVENT,
                                              new AstVarRef{flp, m_actionEventp, VAccess::READ}}},
                nullptr};
            // Beside the process of the assertion, in the scope of its generate blocks
            (m_assertCoverp ? static_cast<AstNodeProcedure*>(m_assertCoverp) : m_procedurep)
                ->addNextHere(m_actionReactivep);
        }
        // The process running an entry, which first takes its values from the queues
        AstBegin* const instancep = new AstBegin{flp, "", nullptr, true};
        AstNodeStmt* queuesp = nullptr;
        std::unordered_map<AstVar*, AstVar*> valueps;
        actionsp->foreachAndNext([&](AstVarRef* refp) {
            AstVar* const varp = refp->varp();
            if (!varp->lifetime().isAutomatic() || ownps.count(varp)) return;
            AstVar*& valuepr = valueps[varp];
            if (!valuepr) {
                // Push the value at the decision, pop it in the entry's process
                AstNodeDType* const dtypep = varp->dtypep();
                AstVar* const queuep = newTemp("Queue", newQueueDTypep(flp, dtypep));
                queuep->setIgnoreSchedWrite();
                AstVarRef* const readp = new AstVarRef{flp, varp, VAccess::READ};
                readp->user2(1);
                queuesp = AstNode::addNext(queuesp, newQueuePush(flp, queuep, readp));
                valuepr = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Value"), dtypep};
                valuepr->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                instancep->addDeclsp(valuepr);
                instancep->addStmtsp(new AstAssign{flp,
                                                   new AstVarRef{flp, valuepr, VAccess::WRITE},
                                                   newQueuePop(flp, queuep, dtypep)});
            }
            refp->varp(valuepr);
        });
        // The action keeps the scope of the assertion, under the named blocks of its process,
        // which V3Begin would have added
        std::string scope;
        for (const AstBegin* const beginp : m_namedBeginps) scope += "__DOT__" + beginp->name();
        if (!scope.empty()) {
            actionsp->foreachAndNext(
                [&](AstScopeName* namep) { namep->scopeAttr(scope + namep->scopeAttr()); });
        }
        instancep->addStmtsp(actionsp);
        // Each entry is run by a process of its own, starting in the Reactive region
        AstFork* const forkp = new AstFork{flp, VJoinType::JOIN_NONE};
        forkp->immediateStart(true);
        forkp->addForksp(new AstForkItem{flp, instancep});
        // Run every pending entry
        AstVar* const pendingp = newTemp("Pending", m_modp->findUInt32DType());
        pendingp->setIgnoreSchedWrite();
        AstLoop* const loopp = new AstLoop{flp};
        loopp->addStmtsp(new AstLoopTest{flp, loopp, new AstVarRef{flp, pendingp, VAccess::READ}});
        loopp->addStmtsp(new AstAssign{
            flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
            new AstSub{flp, new AstVarRef{flp, pendingp, VAccess::READ}, new AstConst{flp, 1}}});
        loopp->addStmtsp(forkp);
        m_actionReactivep->addStmtsp(loopp);
        queuesp = AstNode::addNext(
            queuesp, new AstAssign{flp, new AstVarRef{flp, pendingp, VAccess::WRITE},
                                   new AstAdd{flp, new AstVarRef{flp, pendingp, VAccess::READ},
                                              new AstConst{flp, 1}}});
        return AstNode::addNext(
            queuesp,
            new AstFireEvent{flp, new AstVarRef{flp, m_actionEventp, VAccess::WRITE}, false});
    }

    // A procedural concurrent assertion queues a pending instance at its statement, with the
    // values of its automatic inputs, and the instance matures in the Observed region unless a
    // flush point of its process, or a Kill, flushes it before (IEEE 1800-2023 16.14.6, 20.11).
    // A matured instance begins its attempt there if its leading clock occurred in the time
    // step, else at the next one. 'beginsp' is the attempt's begin, 'clockp' its leading clock.
    // Return what queues the instance.
    AstNodeStmt* newMatureInstance(AstNodeCoverOrAssert* nodep, AstNodeStmt* beginsp,
                                   AstSenTree* clockp) {
        FileLine* const flp = nodep->fileline();
        AstNodeDType* const u32p = m_modp->findUInt32DType();
        AstNodeDType* const u64p = m_modp->findUInt64DType();
        const auto newStatic = [&](const string& name, AstNodeDType* dtypep) {
            AstVar* const varp = newModuleTemp(flp, m_actionNames.get(name), dtypep, m_modp);
            varp->lifetime(VLifetime::STATIC_EXPLICIT);
            varp->setIgnoreSchedWrite();
            return varp;
        };
        const auto rd = [&](AstVar* varp) { return new AstVarRef{flp, varp, VAccess::READ}; };
        const auto wr = [&](AstVar* varp) { return new AstVarRef{flp, varp, VAccess::WRITE}; };
        const auto incp = [&](AstVar* varp, int delta) -> AstNodeStmt* {
            AstNodeExpr* const onep
                = new AstConst{flp, AstConst::WidthedValue{}, varp->width(), 1};
            AstNodeExpr* const valuep
                = delta > 0 ? static_cast<AstNodeExpr*>(new AstAdd{flp, rd(varp), onep})
                            : new AstSub{flp, rd(varp), onep};
            return new AstAssign{flp, wr(varp), valuep};
        };
        // The values of the sampled value functions at the clock, as the attempt may begin
        // after their registers updated (IEEE 1800-2023 16.9.3)
        std::vector<AstVarRef*> pastRefps;
        beginsp->foreach([&](AstVarRef* refp) {
            // Already sampled only if wrapped itself: the node before a list element, as of an
            // unsigned format argument, is its preceding sibling, not its parent
            const AstSampled* const sampledp = VN_CAST(refp->backp(), Sampled);
            if (refp->access().isReadOnly() && m_pastVarps.count(refp->varp())
                && !(sampledp && sampledp->exprp() == refp)) {
                pastRefps.push_back(refp);
            }
        });
        for (AstVarRef* const refp : pastRefps) {
            VNRelinker handle;
            refp->unlinkFrBack(&handle);
            AstSampled* const sampledp = newSampledExpr(refp);
            sampledp->user1(1);
            handle.relink(sampledp);
            v3Global.setHasSampled();
        }
        // The automatic inputs, with their values at the statement (IEEE 1800-2023 16.14.6.1)
        std::unordered_set<const AstVar*> declps;
        beginsp->foreach([&](const AstVar* varp) { declps.insert(varp); });
        std::vector<AstVar*> inputps;
        std::unordered_map<AstVar*, std::vector<AstVarRef*>> refps;
        beginsp->foreach([&](AstVarRef* refp) {
            AstVar* const varp = refp->varp();
            if (!varp->lifetime().isAutomatic() || declps.count(varp) || m_pastVarps.count(varp)) {
                return;
            }
            std::vector<AstVarRef*>& varRefps = refps[varp];
            if (varRefps.empty()) inputps.push_back(varp);
            varRefps.push_back(refp);
        });
        // The flushes of the process (IEEE 1800-2023 16.14.6.2), see addObsFlushes
        if (!m_matureEpochp) {
            m_matureEpochp = newStatic("FlushEpoch", u32p);
            m_obsFlushp = AstNode::addNext(m_obsFlushp, incp(m_matureEpochp, 1));
        }
        AstVar* const eventp
            = newStatic("MatureEvent", m_modp->findBasicDType(VBasicDTypeKwd::EVENT));
        v3Global.setHasEvents();
        AstVar* const pendingp = newStatic("Pending", u32p);
        AstVar* const maturedp = newStatic("Matured", u32p);
        AstVar* const epochQp = newStatic("EpochQueue", newQueueDTypep(flp, u32p));
        AstVar* const killQp = newStatic("KillQueue", newQueueDTypep(flp, u32p));
        AstVar* const clkQp = newStatic("ClockQueue", newQueueDTypep(flp, u64p));
        AstVar* const epochp = newStatic("Epoch", u32p);
        AstVar* const killp = newStatic("Kill", u32p);
        AstVar* const clkCountp = newStatic("ClockCount", u64p);
        AstVar* const clkTimep = newStatic("ClockTime", u64p);
        // Never occurred
        m_modp->addStmtsp(new AstInitialStatic{
            flp,
            new AstAssign{flp, wr(clkTimep),
                          new AstNot{flp, new AstConst{flp, AstConst::WidthedValue{}, 64, 0}}}});
        const auto newTimep
            = [&]() { return new AstCExpr{flp, "vlSymsp->_vm_contextp__->time()", 64}; };
        // At the statement
        AstNodeStmt* queuesp = nullptr;
        // Matured, kept for the clock
        AstNodeStmt* keepsp = nullptr;
        // Flushed
        AstNodeStmt* dropsp = nullptr;
        // Begun
        AstBegin* const beginp = new AstBegin{flp, "", nullptr, true};
        for (AstVar* const varp : inputps) {
            AstNodeDType* const dtypep = varp->dtypep();
            AstVar* const pendQp = newStatic("PendQueue", newQueueDTypep(flp, dtypep));
            AstVar* const matQp = newStatic("MatQueue", newQueueDTypep(flp, dtypep));
            queuesp = AstNode::addNext(queuesp, newQueuePush(flp, pendQp, rd(varp)));
            keepsp = AstNode::addNext(keepsp,
                                      newQueuePush(flp, matQp, newQueuePop(flp, pendQp, dtypep)));
            dropsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
                dropsp, newQueuePop(flp, pendQp, dtypep)->makeStmt());
            AstVar* const copyp
                = new AstVar{flp, VVarType::BLOCKTEMP, m_actionNames.get("Input"), dtypep};
            copyp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            beginp->addDeclsp(copyp);
            beginp->addStmtsp(new AstAssign{flp, wr(copyp), newQueuePop(flp, matQp, dtypep)});
            for (AstVarRef* const refp : refps[varp]) {
                refp->varp(copyp);
                // Its value at the statement, not a sample
                if (AstSampled* const sampledp = VN_CAST(refp->backp(), Sampled)) {
                    if (sampledp->exprp() == refp) {
                        sampledp->replaceWith(refp->unlinkFrBack());
                        VL_DO_DANGLING(pushDeletep(sampledp), sampledp);
                    }
                }
            }
        }
        queuesp = AstNode::addNext(queuesp, newQueuePush(flp, epochQp, rd(m_matureEpochp)));
        queuesp = AstNode::addNext(queuesp, newQueuePush(flp, killQp, newKillCountp(flp)));
        queuesp = AstNode::addNext(queuesp, incp(pendingp, 1));
        queuesp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
            queuesp, new AstFireEvent{flp, wr(eventp), false});
        // Mature the pending instances
        AstLoop* const matureLoopp = new AstLoop{flp};
        matureLoopp->addStmtsp(new AstLoopTest{flp, matureLoopp, rd(pendingp)});
        matureLoopp->addStmtsp(incp(pendingp, -1));
        matureLoopp->addStmtsp(new AstAssign{flp, wr(epochp), newQueuePop(flp, epochQp, u32p)});
        matureLoopp->addStmtsp(new AstAssign{flp, wr(killp), newQueuePop(flp, killQp, u32p)});
        keepsp = AstNode::addNext<AstNodeStmt, AstNodeStmt>(
            keepsp,
            new AstIf{flp, new AstEq{flp, rd(clkTimep), newTimep()},
                      newQueuePush(flp, clkQp,
                                   new AstSub{flp, rd(clkCountp),
                                              new AstConst{flp, AstConst::WidthedValue{}, 64, 1}}),
                      newQueuePush(flp, clkQp, rd(clkCountp))});
        keepsp = AstNode::addNext(keepsp, incp(maturedp, 1));
        AstNodeExpr* const keepCondp
            = new AstLogAnd{flp, new AstEq{flp, rd(epochp), rd(m_matureEpochp)},
                            new AstEq{flp, rd(killp), newKillCountp(flp)}};
        matureLoopp->addStmtsp(new AstIf{flp, keepCondp, keepsp, dropsp});
        // Begin the matured instances whose leading clock occurred since they matured, in
        // their order
        AstCMethodHard* const frontp
            = new AstCMethodHard{flp, rd(clkQp), VCMethod::ARRAY_AT,
                                 new AstConst{flp, AstConst::WidthedValue{}, 32, 0}};
        frontp->dtypeFrom(u64p);
        AstLoop* const beginLoopp = new AstLoop{flp};
        beginLoopp->addStmtsp(new AstLoopTest{
            flp, beginLoopp,
            new AstLogAnd{flp, rd(maturedp), new AstLt{flp, frontp, rd(clkCountp)}}});
        beginLoopp->addStmtsp(incp(maturedp, -1));
        beginLoopp->addStmtsp(newQueuePop(flp, clkQp, u64p)->makeStmt());
        beginp->addStmtsp(beginsp);
        // In a process of its own, with its own copies of the inputs
        AstFork* const beginForkp = new AstFork{flp, VJoinType::JOIN_NONE};
        beginForkp->immediateStart(true);
        beginForkp->addForksp(new AstForkItem{flp, beginp});
        beginLoopp->addStmtsp(beginForkp);
        AstSenTree* const senTreep
            = new AstSenTree{flp, new AstSenItem{flp, VEdgeType::ET_EVENT, rd(eventp)}};
        senTreep->addSensesp(clockp->sensesp()->cloneTree(true));
        AstAlwaysObserved* const runnerp = new AstAlwaysObserved{flp, senTreep, matureLoopp};
        runnerp->addStmtsp(beginLoopp);
        // The occurrences of the leading clock
        AstAlways* const clockAlwaysp
            = new AstAlways{flp, VAlwaysKwd::ALWAYS, clockp, incp(clkCountp, 1)};
        clockAlwaysp->addStmtsp(new AstAssign{flp, wr(clkTimep), newTimep()});
        m_procedurep->addNextHere(runnerp);
        m_procedurep->addNextHere(clockAlwaysp);
        return newIfAssertOn(nodep->controlVarp(), queuesp, nodep->directive(), nodep->userType());
    }

    // The action lists of a concurrent assertion that run in a process of their own: a jump that
    // V3LinkJump made to a block outside them cannot leave that process. The loop exit after a
    // $finish in a loop of the procedure only ends that loop, so it is dropped and the $finish
    // stays; any other such jump is reported as unsupported. A cover deleted without coverage
    // takes its actions along, so it is left alone.
    void dropOutwardActionJumps(AstNodeCoverOrAssert* nodep) {
        const AstCover* const coverp = VN_CAST(nodep, Cover);
        if (coverp && !coverp->isSeqEvent() && !v3Global.opt.coverageUser()) return;
        // Only for concurrent assertions; an AstAssertIntrinsic is always immediate
        UASSERT_OBJ(!nodep->immediate(), nodep, "Immediate assertion");
        AstNode* failsp = nullptr;
        if (AstAssert* const assertp = VN_CAST(nodep, Assert)) failsp = assertp->failsp();
        std::unordered_set<const AstJumpBlock*> innerps;
        std::vector<AstJumpGo*> gops;
        for (AstNode* const listp : {failsp, static_cast<AstNode*>(nodep->passsp())}) {
            for (AstNode* np = listp; np; np = np->nextp()) {
                np->foreach([&](const AstJumpBlock* blockp) { innerps.insert(blockp); });
            }
        }
        for (AstNode* const listp : {failsp, static_cast<AstNode*>(nodep->passsp())}) {
            for (AstNode* np = listp; np; np = np->nextp()) {
                np->foreach([&](AstJumpGo* gop) {
                    if (!innerps.count(gop->blockp())) gops.push_back(gop);
                });
            }
        }
        for (AstJumpGo* const gop : gops) {
            // As V3LinkJump visit(AstFinish) adds it, and nothing else does: next to the
            // $finish, with the $finish's own file line, to the jump block around the loop (which
            // V3Width may have converted from a foreach)
            const AstFinish* const finishp = VN_CAST(gop->backp(), Finish);
            const bool finishExit
                = finishp && finishp->nextp() == gop && gop->fileline() == finishp->fileline();
            if (finishExit) {
                // Never the head of a list, it follows its $finish
                VL_DO_DANGLING(pushDeletep(gop->unlinkFrBack()), gop);
                continue;
            }
            gop->v3warn(E_UNSUPPORTED, "Unsupported: control transfer out of a concurrent"
                                       " assertion action block, which runs in a process of"
                                       " its own");
            // Keep the action list non-empty
            gop->replaceWith(new AstBegin{gop->fileline(), "", nullptr, true});
            VL_DO_DANGLING(pushDeletep(gop), gop);
        }
    }

    void visitAssertionIterate(AstNodeCoverOrAssert* nodep, AstNodeStmt* failsp) {
        FileLine* const flp = nodep->fileline();
        const bool obsDeferred = nodep->userType() == VAssertType::OBSERVED_DEFERRED_IMMEDIATE;
        if (obsDeferred && (!v3Global.opt.timing().isSetTrue() || m_ftaskp || m_inSpawnedFork)) {
            if (v3Global.opt.timing().isSetFalse()) {
                nodep->v3warn(E_NOTIMING,
                              "Observed deferred immediate assertion requires --timing");
            } else if (!v3Global.opt.timing().isSetTrue()) {
                nodep->v3warn(E_NEEDTIMINGOPT,
                              "Use --timing or --no-timing to specify how observed deferred "
                              "immediate assertions should be handled");
            } else {
                // Under fork...join_any/join_none, instances of a branch may run at once, but
                // would share one queue
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Observed deferred immediate assertion in "
                                  << (m_ftaskp ? "a task or function."
                                               : "fork...join_any or fork...join_none."));
            }
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        if (m_beginp && nodep->name() == "") nodep->name(m_beginp->name());
        VL_RESTORER(m_inlineAction);
        m_inlineAction = false;
        // The waits of a concurrent assertion's attempts and actions are not those of the
        // process, so not its flush points
        struct WaitsIsolation final {
            std::vector<AstNode*>& m_waitsr;  // The process's waits
            std::vector<AstNode*> m_saved;  // Those before the assertion
            const bool m_on;  // Isolating
            WaitsIsolation(std::vector<AstNode*>& waitsr, bool on)
                : m_waitsr{waitsr}
                , m_on{on} {
                if (m_on) std::swap(m_saved, m_waitsr);
            }
            ~WaitsIsolation() {
                if (m_on) std::swap(m_saved, m_waitsr);
            }
        };
        const WaitsIsolation waitsIsolation{m_obsWaitsp, !nodep->immediate()};
        // A const cast takes its value when a procedural concurrent assertion is queued, at its
        // statement (IEEE 1800-2023 16.14.6.1). The attempt gets its own copy (see V3Fork), and
        // so does each entry of its queued actions (see newQueuedAction).
        // Inner casts first, so an outer one reads their copies. A cast of variables declared
        // in the assertion, e.g. in an action block, only has their values there.
        // Those of a concurrent assertion in an action block are its own.
        std::vector<AstConstCast*> castps;  // In post-order, so inner ones first
        const std::function<void(AstNode*)> collect = [&](AstNode* np) {
            for (; np; np = np->nextp()) {
                const AstNodeCoverOrAssert* const assertp = VN_CAST(np, NodeCoverOrAssert);
                if (assertp && !assertp->immediate()) continue;
                collect(np->op1p());
                collect(np->op2p());
                collect(np->op3p());
                collect(np->op4p());
                if (AstConstCast* const castp = VN_CAST(np, ConstCast)) castps.push_back(castp);
            }
        };
        collect(nodep->op1p());
        collect(nodep->op2p());
        collect(nodep->op3p());
        collect(nodep->op4p());
        std::unordered_set<const AstVar*> localps;
        nodep->foreach([&](const AstVar* varp) { localps.insert(varp); });
        for (AstConstCast* const castp : castps) {
            AstNodeExpr* const exprp = castp->lhsp()->unlinkFrBack();
            const bool local = exprp->exists([&](const AstNode* np) {
                const AstNodeVarRef* const refp = VN_CAST(np, NodeVarRef);
                return VN_IS(np, LambdaArgRef) || (refp && localps.count(refp->varp()));
            });
            if (m_procedurep && !nodep->immediate() && !local) {
                FileLine* const castFlp = castp->fileline();
                AstVar* const varp
                    = newModuleTemp(castFlp, m_actionNames.get("Const"), exprp->dtypep(), m_modp);
                varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                nodep->addHereThisAsNext(
                    new AstAssign{castFlp, new AstVarRef{castFlp, varp, VAccess::WRITE}, exprp});
                castp->replaceWith(new AstVarRef{castFlp, varp, VAccess::READ});
            } else {
                castp->replaceWith(exprp);
            }
            VL_DO_DANGLING(pushDeletep(castp), castp);
        }

        // Only a concurrent assertion has a property or sequence expression, so visit(AstFuture)
        // rejects future value functions in immediate assertions and $cast (IEEE 1800-2023 16.9.4)
        if (!nodep->immediate()) AssertDeFutureVisitor{nodep->propp(), m_modp, m_modPastNum++};

        iterateAndNextNull(nodep->sentreep());
        {
            // The actions of a concurrent assertion run in a process of their own, so its
            // nested assertions are not of the procedure's process
            VL_RESTORER(m_inConcurrentAction);
            m_inConcurrentAction |= !nodep->immediate();
            if (AstAssert* const assertp = VN_CAST(nodep, Assert)) {
                iterateAndNextNull(assertp->failsp());
            } else if (AstAssertIntrinsic* const assertp = VN_CAST(nodep, AssertIntrinsic)) {
                iterateAndNextNull(assertp->failsp());
            } else {
                // Called only for an Assert, AssertIntrinsic or Cover (visit(AstRestrict) has its
                // own iteration)
                iterateAndNextNull(VN_AS(nodep, Cover)->coverincsp());
            }
            iterateAndNextNull(nodep->passsp());
        }
        AstSenTree* sentreep = nodep->sentreep();
        AstSenTree* procClockp = nullptr;  // Leading clock of a procedural assertion
        if (nodep->immediate()) {
            UASSERT_OBJ(!sentreep, nodep, "Immediate assertions don't have sensitivity");
        } else {
            UASSERT_OBJ(sentreep, nodep, "Concurrent assertions must have sensitivity");
            // Explicit inline clock differs from the enclosing always: hoist
            // and warn. To support this need queue of asserts to activate.
            if (m_procedurep && !nodep->senFromAlways()) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Procedural concurrent assertion with"
                              " clocking event inside always (IEEE 1800-2023 16.14.6)");
                // Its actions move with it, out of the procedure
                dropOutwardActionJumps(nodep);
                // Leave an empty statement, so a block of the procedure whose only statement
                // this was keeps a body (V3LinkJump's disable target wrapper expects one)
                nodep->replaceWith(new AstBegin{flp, "", nullptr, true});
                m_procedurep->addNext(
                    new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, nodep});
                return;  // Later iterate will pick up
            }
            // A task is not a process, so the assertion gets its own beside the task
            if (m_ftaskp) {
                // Its actions move with it, out of the task
                dropOutwardActionJumps(nodep);
                // As above, for a block under a fork item in the task
                nodep->replaceWith(new AstBegin{flp, "", nullptr, true});
                m_ftaskp->addNextHere(
                    new AstAlways{flp, VAlwaysKwd::ASSERT_COVER, nullptr, nodep});
                return;  // Later iterate will pick up
            }
            sentreep->unlinkFrBack();
            if (m_procedurep) {
                procClockp = sentreep;
                sentreep = nullptr;
            }
        }
        // The attempt of a property expression runs in a forked process (assertBody), with its
        // actions
        if (!nodep->immediate() && v3Global.opt.timing().isSetTrue()) {
            const AstPropSpec* const specp = VN_CAST(nodep->propp(), PropSpec);
            const AstNode* propp = specp ? specp->propp() : nodep->propp();
            // V3AssertPre samples the whole property; visit(AstSampled) removes that later
            if (const AstSampled* const sampledp = VN_CAST(propp, Sampled)) {
                propp = sampledp->exprp();
            }
            if (VN_IS(propp, PExpr)) dropOutwardActionJumps(nodep);
        }
        //
        const string& message = nodep->name();
        AstNodeStmt* passsp = nodep->passsp();
        if (passsp) passsp->unlinkFrBackWithNext();
        if (AstAssert* const assertp = VN_CAST(nodep, Assert)) {
            failsp = assertp->failsp();
        } else if (AstAssertIntrinsic* const assertp = VN_CAST(nodep, AssertIntrinsic)) {
            failsp = assertp->failsp();
        }
        if (failsp) failsp->unlinkFrBackWithNext();

        bool selfDestruct = false;
        bool passspGated = false;
        const AstCover* const coverp = VN_CAST(nodep, Cover);
        // A sequence event control is not an assertion directive; no assertion control
        const bool seqEvent = coverp && coverp->isSeqEvent();
        if (coverp) {
            ++m_statCover;
            if (seqEvent) {
                // Keep the event-fire action, with no coverage bucket
            } else if (!v3Global.opt.coverageUser()) {
                selfDestruct = true;
            } else {
                // V3Coverage assigned us a bucket to increment.
                AstCoverInc* const covincp = VN_AS(coverp->coverincsp(), CoverInc);
                UASSERT_OBJ(covincp, coverp, "Missing AstCoverInc under assertion");
                covincp->unlinkFrBackWithNext();  // next() might have  AstAssign for trace
                if (message != "") covincp->declp()->comment(AstNode::prettyName(message));
                // IEEE 1800-2023 16.4.2: Deferred coverage is flushed like a pending report
                AstNodeStmt* creditsp = covincp;
                if (obsDeferred) {
                    DeferredReportQueues queues{nullptr, nullptr, nullptr, nodep};
                    creditsp = newObservedDeferredCall(flp, covincp, queues);
                    if (passsp) passsp = newObservedDeferredAction(flp, passsp, nodep);
                }
                if (passsp) {
                    passsp = newIfAssertPassOn(nodep->controlVarp(), passsp, nodep->directive(),
                                               nodep->userType(),
                                               /*vacuous=*/false);
                    passspGated = true;
                    passsp = AstNode::addNext(creditsp, passsp);
                } else {
                    passsp = creditsp;
                }
            }
        } else if (VN_IS(nodep, Assert) || VN_IS(nodep, AssertIntrinsic)) {
            if (nodep->immediate()) {
                ++m_statAsImm;
            } else {
                ++m_statAsNotImm;
            }
            if (!failsp)
                failsp = newFireAssertUnchecked(
                    nodep, VN_IS(nodep, AssertIntrinsic) ? "'$cast' failed." : "'assert' failed.");
            if (obsDeferred) {
                if (passsp) passsp = newObservedDeferredAction(flp, passsp, nodep);
                if (failsp) failsp = newObservedDeferredAction(flp, failsp, nodep);
            }
        } else {
            nodep->v3fatalSrc("Unknown node type");
        }

        VL_RESTORER(m_passsp);
        VL_RESTORER(m_failsp);
        VL_RESTORER(m_assertp);
        m_passsp = passsp;
        m_failsp = failsp;
        m_assertp = nodep;
        {
            VL_RESTORER_CLEAR(m_clauseActionsp);
            // Queue construction rewrites captured references. Make copies before any clause
            // takes the original action, which owns the shared static declarations.
            bool usedPass = false;
            bool usedFail = false;
            nodep->propp()->foreach([&](const AstPExprClause* const clausep) {
                AstNodeStmt* const actionp = clausep->pass() ? passsp : failsp;
                if (!actionp) return;
                bool& used = clausep->pass() ? usedPass : usedFail;
                if (used) {
                    m_clauseActionsp.emplace(clausep,
                                             V3AssertCommon::cloneAction(actionp, m_actionNames));
                }
                used = true;
            });
            iterate(nodep->propp());
            for (const auto& entry : m_clauseActionsp) pushDeletep(entry.second);
        }

        AstNode* propExprp;
        AstNodeExpr* disablep = nullptr;
        AstNodeExpr* matchCountp = nullptr;
        if (AstPropSpec* const specp = VN_CAST(nodep->propp(), PropSpec)) {
            propExprp = specp->propp()->unlinkFrBack();
            if (specp->disablep()) disablep = specp->disablep()->unlinkFrBack();
            matchCountp = specp->matchCountp();
        } else {
            propExprp = nodep->propp()->unlinkFrBack();
        }
        // A procedural concurrent assertion matures in the Observed region, see
        // newMatureInstance, unless it is lowered by V3AssertNfa, in a fork branch or an action
        // of a concurrent assertion, processes other than the procedure's, without timing, or
        // has an action that stays inline
        const bool isPExpr = VN_IS(propExprp, PExpr);
        bool mature = procClockp && VN_IS(nodep, Assert) && !nodep->nfaLowered() && !m_inForkBranch
                      && !m_inConcurrentAction && !m_ftaskp && !seqEvent && !selfDestruct
                      && v3Global.opt.timing().isSetTrue();
        if (mature && isPExpr) mature = !m_inlineAction;
        if (mature && !isPExpr) {
            mature
                = !(passsp && actionStaysInline(passsp)) && !(failsp && actionStaysInline(failsp));
            // Its actions run in the Reactive region (IEEE 1800-2023 4.4.2.6)
            if (mature && passsp) passsp = newQueuedAction(flp, passsp);
            if (mature && failsp) failsp = newQueuedAction(flp, failsp);
        }
        bool passspAlreadyGated = false;
        if (passsp && VN_IS(passsp, If)) passspAlreadyGated = VN_AS(passsp, If)->user1();
        if (passsp && !passspGated && !passspAlreadyGated && !VN_IS(propExprp, PExpr)
            && !seqEvent) {
            passsp = newIfAssertPassOn(nodep->controlVarp(), passsp, nodep->directive(),
                                       nodep->userType(),
                                       /*vacuous=*/false);
        }
        if (failsp && !VN_IS(propExprp, PExpr)) {
            failsp = newIfAssertFailOn(nodep->controlVarp(), failsp, nodep->directive(),
                                       nodep->userType());
        }
        if (coverp && matchCountp && passsp) {
            // Convert the match count into a loop that decrements a temporary variable until it
            // reaches zero.
            matchCountp->unlinkFrBack();
            AstVar* const remainingp = new AstVar{
                flp, VVarType::MODULETEMP, m_matchCountNames.get(""), matchCountp->dtypep()};
            remainingp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(remainingp);
            AstNodeStmt* const replaysp
                = new AstAssign{flp, new AstVarRef{flp, remainingp, VAccess::WRITE}, matchCountp};
            AstLoop* const loopp = new AstLoop{flp};
            loopp->addStmtsp(
                new AstLoopTest{flp, loopp, new AstVarRef{flp, remainingp, VAccess::READ}});
            loopp->addStmtsp(passsp);
            loopp->addStmtsp(
                new AstAssign{flp, new AstVarRef{flp, remainingp, VAccess::WRITE},
                              new AstSub{flp, new AstVarRef{flp, remainingp, VAccess::READ},
                                         new AstConst{flp, AstConst::WidthedValue{},
                                                      remainingp->dtypep()->width(), 1}}});
            replaysp->addNext(loopp);
            passsp = replaysp;
        }
        // A discarded cover runs no action, so also not at the end of simulation.
        if (selfDestruct) {
            if (AstPExpr* const pexprp = VN_CAST(propExprp, PExpr)) {
                if (pexprp->finalp()) pushDeletep(pexprp->finalp()->unlinkFrBack());
            }
        }
        AstNodeStmt* bodysp = assertBody(nodep, propExprp, passsp, failsp);
        // A matured attempt begins at once, in the Observed region
        if (mature) {
            if (AstFork* const forkp = VN_CAST(bodysp, Fork)) forkp->immediateStart(true);
        }
        if (disablep) bodysp = new AstIf{flp, new AstLogNot{flp, disablep}, bodysp};
        if (mature) {
            bodysp = newMatureInstance(nodep, bodysp, procClockp);
            procClockp = nullptr;
        } else if (!seqEvent && !nodep->nfaLowered()) {
            // NFA entry is already gated. Off does not suppress an in-flight outcome.
            bodysp = newIfAssertOn(nodep->controlVarp(), bodysp, nodep->directive(),
                                   nodep->userType());
        }
        if (procClockp) VL_DO_DANGLING(pushDeletep(procClockp), procClockp);
        bodysp->foreach([](AstNodeVarRef* nodep) {
            nodep->fileline()->modifyWarnOff(V3ErrorCode::SYNCASYNCNET, true);
        });

        if (passsp && !passsp->backp()) VL_DO_DANGLING(pushDeletep(passsp), passsp);
        if (failsp && !failsp->backp()) VL_DO_DANGLING(pushDeletep(failsp), failsp);

        // Install it
        if (selfDestruct) {
            // Delete it after making the tree.  This way we can tell the user
            // if it wasn't constructed nicely or has other errors without needing --coverage.
            VL_DO_DANGLING(bodysp->deleteTree(), bodysp);
            if (sentreep) VL_DO_DANGLING(sentreep->deleteTree(), sentreep);
            nodep->unlinkFrBack();
        } else {
            if (sentreep) {
                // The process of the concurrent assertion is clocked by it
                UASSERT_OBJ(m_assertCoverp, nodep, "Concurrent assertion not in its process");
                m_assertCoverp->keyword(VAlwaysKwd::ALWAYS);
                m_assertCoverp->sentreep(sentreep);
            }
            nodep->replaceWith(bodysp);
        }
        // Bye
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    bool isEmptyStmt(AstNode* nodep) {
        if (!nodep) return true;
        if (AstBegin* const beginp = VN_CAST(nodep, Begin)) {
            if (beginp->declsp()) return false;
            for (AstNode* const stmtp : beginp->stmtspList()) {
                if (!isEmptyStmt(stmtp)) return false;
            }
            return true;
        }
        return false;
    }

    // VISITORS
    void visit(AstIf* nodep) override {
        if (!nodep->user1SetOnce()) {
            if (nodep->uniquePragma() || nodep->unique0Pragma()) {
                const AstIf* ifp = nodep;
                AstNodeExpr* propp = nullptr;
                bool hasDefaultElse = false;
                do {
                    // If this statement ends with 'else if', then nextIf will point to the
                    // nextIf statement.  Otherwise it will be null.
                    const AstIf* const nextifp = dynamic_cast<AstIf*>(ifp->elsesp());
                    iterateAndNextNull(ifp->condp());

                    // Recurse into the true case.
                    iterateAndNextNull(ifp->thensp());

                    // If the last else is not an else if, recurse into that too.
                    if (ifp->elsesp() && !nextifp) {  //
                        iterateAndNextNull(ifp->elsesp());
                    }

                    // Build a bitmask of the true predicates
                    AstNodeExpr* const predp = ifp->condp()->cloneTreePure(false);
                    if (propp) {
                        propp = new AstConcat{nodep->fileline(), predp, propp};
                    } else {
                        propp = predp;
                    }

                    // Record if this ends with an 'else' that does not have an if.  An else
                    // holding only CoverIncs is one V3Coverage added; a source 'else ;' still
                    // holds an empty begin.
                    if (!nextifp) {
                        for (const AstNode* const stmtp : ifp->elsespList()) {
                            if (!VN_IS(stmtp, CoverInc)) {
                                hasDefaultElse = true;
                                break;
                            }
                        }
                    }

                    ifp = nextifp;
                } while (ifp);

                const bool allow_none = nodep->unique0Pragma();

                // Empty case means no property
                if (!propp) propp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};

                // Note: if this ends with an 'else', then we don't need to validate that one of
                // the predicates evaluates to true.
                AstNodeExpr* const ohotp
                    = ((allow_none || hasDefaultElse)
                           ? static_cast<AstNodeExpr*>(new AstOneHot0{nodep->fileline(), propp})
                           : static_cast<AstNodeExpr*>(new AstOneHot{nodep->fileline(), propp}));
                const VAssertType assertType
                    = nodep->uniquePragma() ? VAssertType::UNIQUE : VAssertType::UNIQUE0;
                // Move, not clone, as the branches might declare referenced variables
                VNRelinker relinker;
                nodep->unlinkFrBack(&relinker);
                AstIf* const checkifp
                    = new AstIf{nodep->fileline(), new AstLogNot{nodep->fileline(), ohotp},
                                newFireAssert(nodep, VAssertDirectiveType::VIOLATION_IF,
                                              assertType, "'unique if' statement violated"),
                                nodep};
                checkifp->isBoundsCheck(true);  // To avoid LATCH warning
                checkifp->branchPred(VBranchPred::BP_UNLIKELY);
                relinker.relink(checkifp);
                return;
            }
        }

        iterateChildren(nodep);

        if (nodep->user2()) {
            // Combine consecutive assertOn checks if possible
            if (AstIf* const backp = VN_CAST(nodep->backp(), If)) {
                if (backp->nextp() == nodep  //
                    && backp->user2()  //
                    && backp->condp()->sameTree(nodep->condp())) {
                    ++m_statAssertOnCombined;
                    backp->addThensp(nodep->thensp()->unlinkFrBackWithNext());
                    nodep->unlinkFrBack();
                    VL_DO_DANGLING(pushDeletep(nodep), nodep);
                    return;
                }
            }
            // Combine nested assertOn checks if possible
            if (nodep->thensp() && !nodep->thensp()->nextp() && isEmptyStmt(nodep->elsesp())) {
                AstIf* const checkp = VN_CAST(nodep->thensp(), If);
                if (checkp  //
                    && checkp->user2()  //
                    && checkp->condp()->sameTree(nodep->condp())) {
                    ++m_statAssertOnCombined;
                    nodep->addThensp(checkp->thensp()->unlinkFrBackWithNext());
                    VL_DO_DANGLING(pushDeletep(checkp->unlinkFrBack()), checkp);
                    return;
                }
            }
            return;
        }

        // Swap assertOn check with single statement 'if' statement to bubble up for combining
        // Note we can't just swap the conditions as they two Ifs have different flags,
        // so swapping the Ifs themeselves then swapping back the bodies.
        if (nodep->condp()->isPure()) {
            if (nodep->thensp() && !nodep->thensp()->nextp() && isEmptyStmt(nodep->elsesp())) {
                AstIf* const checkp = VN_CAST(nodep->thensp(), If);
                if (checkp && checkp->user2()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(checkp->unlinkFrBack());
                    nodep->addThensp(checkp->thensp()->unlinkFrBackWithNext());
                    checkp->addThensp(nodep);
                    return;
                }
            }
            if (nodep->elsesp() && !nodep->elsesp()->nextp() && isEmptyStmt(nodep->thensp())) {
                AstIf* const checkp = VN_CAST(nodep->elsesp(), If);
                if (checkp && checkp->user2()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(checkp->unlinkFrBack());
                    nodep->addElsesp(checkp->thensp()->unlinkFrBackWithNext());
                    checkp->addThensp(nodep);
                    return;
                }
            }
        }
    }

    //========== Case assertions
    void visit(AstCase* nodep) override {
        // Introduce temporary variable for AstCase if needed - it is done here and not in V3Case
        // because this phase is before V3Scope and V3Case is not. Doing it before V3Scope ensures
        // that V3Scope will take care of a scope creation
        // We also need to do it before V3Begin, co that pragmas like `unique0` also work correctly
        if (!nodep->exprp()->isPure()) {
            ++m_statLiftedCaseExprs;
            FileLine* const fl = nodep->exprp()->fileline();
            AstVar* const varp = new AstVar{fl, VVarType::BLOCKTEMP, m_caseTempNames.get(nodep),
                                            nodep->exprp()->dtypep()};
            AstNodeExpr* const origp = nodep->exprp()->unlinkFrBack();
            nodep->addHereThisAsNext(
                new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE}, origp});
            nodep->exprp(new AstVarRef{fl, varp, VAccess::READ});
            if (m_ftaskp) {
                varp->funcLocal(true);
                varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
                m_ftaskp->prependDeclsp(varp);
            } else {
                m_modp->prependStmtsp(varp);
            }
            VIsCached::clearCacheTree();
        }
        iterateChildren(nodep);
        if (!nodep->user1SetOnce()) {
            bool has_default = false;
            for (AstCaseItem* const itemp : nodep->itemspList()) {
                if (itemp->isDefault()) has_default = true;
            }
            const AstNodeDType* exprDtypep = nodep->exprp()->dtypep()->skipRefp();

            VAssertType assertType = VAssertType::INTERNAL;
            if (nodep->priorityPragma()) {
                assertType = VAssertType::PRIORITY;
            } else if (nodep->uniquePragma()) {
                assertType = VAssertType::UNIQUE;
            } else if (nodep->unique0Pragma()) {
                assertType = VAssertType::UNIQUE0;
            }

            string valFmt;
            if (exprDtypep->isIntegralOrPacked())
                valFmt = " for '" + cvtToStr(exprDtypep->widthMin()) + "'h%X'";
            if (nodep->fullPragma() || nodep->priorityPragma()) {
                // Need to add a default if there isn't one already
                ++m_statAsFull;
                if (!has_default) {
                    nodep->addItemsp(new AstCaseItem{
                        nodep->fileline(), nullptr /*DEFAULT*/,
                        newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                      nodep->pragmaString() + ", but non-match found" + valFmt,
                                      valFmt.empty() ? nullptr
                                                     : nodep->exprp()->cloneTreePure(false))});
                }
            }
            if (nodep->parallelPragma() || nodep->uniquePragma() || nodep->unique0Pragma()) {
                // Need to check that one, and only one of the case items match at any moment
                // If there's a default, we allow none to match, else exactly one must match
                ++m_statAsFull;
                if (!has_default && !nodep->itemsp()) {
                    // Not parallel, but harmlessly so.
                } else {
                    AstNodeExpr* propp = nullptr;
                    for (AstCaseItem* const itemp : nodep->itemspList()) {
                        AstNodeExpr* itembitp = nullptr;
                        for (AstNodeExpr* const icondp : itemp->condspList()) {
                            AstNodeExpr* onep;
                            if (AstInsideRange* const rcondp = VN_CAST(icondp, InsideRange)) {
                                onep = rcondp->newAndFromInside(
                                    nodep->exprp()->cloneTreePure(true),
                                    rcondp->lhsp()->cloneTreePure(true),
                                    rcondp->rhsp()->cloneTreePure(true));
                            } else if (nodep->casex() || nodep->casez() || nodep->caseInside()) {
                                onep = AstEqWild::newTyped(itemp->fileline(),
                                                           nodep->exprp()->cloneTreePure(false),
                                                           icondp->cloneTreePure(false));
                            } else {
                                onep = AstEq::newTyped(icondp->fileline(),
                                                       nodep->exprp()->cloneTreePure(false),
                                                       icondp->cloneTreePure(false));
                            }
                            // OR together all conditions within the same case item
                            if (onep) {
                                if (itembitp) {
                                    itembitp = new AstOr{icondp->fileline(), onep, itembitp};
                                } else {
                                    itembitp = onep;
                                }
                            }
                        }
                        if (itembitp) {
                            if (propp) {
                                propp = new AstConcat{itemp->fileline(), itembitp, propp};
                            } else {
                                propp = itembitp;
                            }
                        }
                    }
                    // Empty case means no property
                    if (!propp) propp = new AstConst{nodep->fileline(), AstConst::BitFalse{}};
                    const bool allow_none = has_default || nodep->unique0Pragma();
                    // The following assertion looks as below.
                    // if (!$onehot(propp)) begin
                    //     if (propp == '0) begin if (!allow_none) $error("none match"); end
                    //     else $error("multiple match");
                    // end
                    AstNodeExpr* const ohotp = new AstOneHot{nodep->fileline(), propp};
                    AstConst* const zerop = new AstConst{
                        nodep->fileline(), AstConst::WidthedValue{}, propp->width(), 0};
                    AstIf* const ohotIfp
                        = new AstIf{nodep->fileline(), new AstLogNot{nodep->fileline(), ohotp}};
                    AstIf* const zeroIfp = new AstIf{
                        nodep->fileline(),
                        new AstEq{nodep->fileline(), propp->cloneTreePure(false), zerop}};
                    AstNodeExpr* const exprp = nodep->exprp();
                    const string pragmaStr = nodep->pragmaString();
                    if (!allow_none)
                        zeroIfp->addThensp(
                            newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                          pragmaStr + ", but none matched" + valFmt,
                                          valFmt.empty() ? nullptr : exprp->cloneTreePure(false)));
                    zeroIfp->addElsesp(
                        newFireAssert(nodep, VAssertDirectiveType::VIOLATION_CASE, assertType,
                                      pragmaStr + ", but multiple matches found" + valFmt,
                                      valFmt.empty() ? nullptr : exprp->cloneTreePure(false)));
                    ohotIfp->addThensp(zeroIfp);
                    ohotIfp->isBoundsCheck(true);  // To avoid LATCH warning
                    ohotIfp->branchPred(VBranchPred::BP_UNLIKELY);
                    nodep->addNotParallelp(ohotIfp);
                }
            }
        }
    }

    void visit(AstFuture* nodep) override {
        nodep->v3error("Future sampled value function called outside property or sequence "
                       "expression (IEEE 16.9.4)");
        nodep->replaceWith(new AstConst{nodep->fileline(), 0});
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    //========== Past
    // True if sentreep has an event that fires in the Observed region
    static bool isObservedEventClock(const AstSenTree* sentreep) {
        // Compiler-made events, of clocking blocks and sequences (the only MODULETEMP events
        // at this stage), fire in the Observed region
        for (const AstSenItem* itemp = sentreep->sensesp(); itemp;
             itemp = VN_AS(itemp->nextp(), SenItem)) {
            const AstNodeVarRef* const refp = itemp->varrefp();
            if (refp && refp->varp()->varType() == VVarType::MODULETEMP
                && refp->varp()->isEvent()) {
                return true;
            }
        }
        return false;
    }

    void visit(AstPast* nodep) override {
        // When clocked in the Observed region, the history of a nested sampled value function
        // would already be updated in the time step
        if (isObservedEventClock(nodep->sentreep())
            && nodep->exprp()->exists([](const AstPast*) { return true; })) {
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: sampled value function clocked by a"
                                         " clocking block or sequence event, of an expression"
                                         " with a nested sampled value function");
            nodep->replaceWith(
                new AstConst{nodep->fileline(), AstConst::DTyped{}, nodep->dtypep()});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (!nodep->propertyTiming()) {
            nodep->initp(nodep->exprp()->cloneTreePure(false));
            { DefaultSampledValueVisitor{nodep->initp()}; }
        }
        AstNodeExpr* const initp = nodep->initp() ? nodep->initp()->unlinkFrBack() : nullptr;
        iterateChildren(nodep);
        uint32_t ticks = 1;
        if (nodep->ticksp()) {
            UASSERT_OBJ(VN_IS(nodep->ticksp(), Const), nodep,
                        "Expected constant ticks, checked in V3Width");
            ticks = VN_AS(nodep->ticksp(), Const)->toUInt();
        }
        UASSERT_OBJ(ticks >= 1, nodep, "0 tick should have been checked in V3Width");
        AstNodeExpr* const exprp = newSampledExpr(nodep->exprp()->unlinkFrBack());
        AstSenTree* const senTreep = nodep->sentreep()->unlinkFrBack();
        AstNodeExpr* inp = nullptr;
        // Deliberately emitted for every ftask $past; calls outside final take the normal stage
        if (VN_IS(m_procedurep, Final) || m_ftaskp) {
            // A sampling-tick finish reads one stage deeper (IEEE 1800-2023 16.9.3).
            FileLine* const flp = nodep->fileline();
            AstAlways* const alwaysp
                = getDelayedAlways(exprp, initp ? initp->cloneTreePure(false) : nullptr, senTreep,
                                   nodep->ownHistory());
            AstNodeExpr* const betweenTicksp = pastValueRef(alwaysp, flp, ticks, initp);
            AstNodeExpr* const onTickp = pastValueRef(alwaysp, flp, ticks + 1, initp);
            if (initp) VL_DO_DANGLING(pushDeletep(initp), initp);
            AstNodeExpr* const onTickCondp = new AstLogAnd{
                flp, new AstCExpr{flp, "vlSymsp->_vm_contextp__->executingFinal()", 1},
                new AstEq{flp, new AstVarRef{flp, getPastTickTimeVar(alwaysp), VAccess::READ},
                          new AstCExpr{flp, "vlSymsp->_vm_contextp__->finishPendingTime()", 64}}};
            AstCond* const condp = new AstCond{flp, onTickCondp, onTickp, betweenTicksp};
            condp->dtypeFrom(onTickp);
            inp = condp;
        } else {
            inp = getPastValue(exprp, initp, senTreep, ticks, nodep->ownHistory());
        }
        nodep->replaceWith(inp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }

    //========== Move $sampled down to read-only variables
    void visit(AstSampled* nodep) override {
        if (nodep->user1()) return;
        VL_RESTORER(m_inSampled);
        {
            m_inSampled = true;
            iterateChildren(nodep);
        }
        if (nodep->exprp()) {
            nodep->replaceWith(nodep->exprp()->unlinkFrBack());
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstNodeVarRef* nodep) override {
        if (m_inSampled && !nodep->user2() && !nodep->varp()->isTemp()) {
            if (!nodep->access().isReadOnly()) {
                nodep->v3warn(E_UNSUPPORTED,
                              "Unsupported: Write to variable in sampled expression");
            } else {
                VNRelinker relinkHandle;
                nodep->unlinkFrBack(&relinkHandle);
                AstSampled* const newp = newSampledExpr(nodep);
                relinkHandle.relink(newp);
                newp->user1(1);
                v3Global.setHasSampled();
            }
        }
    }
    // Don't sample sensitivities
    void visit(AstSenItem* nodep) override {
        VL_RESTORER(m_inSampled);
        m_inSampled = false;
        iterateChildren(nodep);
    }
    void visit(AstPExprClause* nodep) override {
        AstNodeStmt* stmtsp = nodep->pass() ? m_passsp : m_failsp;
        const auto it = m_clauseActionsp.find(nodep);
        if (it != m_clauseActionsp.end()) {
            stmtsp = it->second;
            m_clauseActionsp.erase(it);
        }
        if (stmtsp) {
            stmtsp->foreachAndNext([](AstNodeVarRef* const refp) {
                // References inside action blocks shouldn't be implicitly sampled
                // m_passsp/m_failsp have been already visited once and refs explicitly sampled
                // are handled already
                refp->user2(1);
            });
        }
        const AstCover* const coverp = VN_CAST(m_assertp, Cover);
        FileLine* const clauseFlp = nodep->fileline();
        if (stmtsp && m_inPExprFinal && m_strongPassOnp) {
            // The end-of-simulation check of a strong property checks attempts, which all have
            // the same outcome there, so act for as many as started with it enabled
            // (IEEE 1800-2023 20.11)
            AstVar* const countp = nodep->pass() ? m_strongPassOnp : m_strongFailOnp;
            AstIf* const ifp = newIfControl(
                new AstNeq{clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::READ},
                           new AstConst{clauseFlp, AstConst::WidthedValue{}, 32, 0}},
                new AstAssign{
                    clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::WRITE},
                    new AstSub{clauseFlp, new AstVarRef{clauseFlp, countp, VAccess::READ},
                               new AstConst{clauseFlp, AstConst::WidthedValue{}, 32, 1}}});
            ifp->addThensp(stmtsp);
            stmtsp = ifp;
        } else if (stmtsp && (m_inPExprFinal || (coverp && coverp->isSeqEvent()))) {
            // The end-of-simulation check runs in a final block, and the attempts of a sequence
            // event control are not assertion attempts, so both keep the controls applying now
            if (nodep->pass()) {
                stmtsp
                    = newIfAssertPassOn(m_assertp->controlVarp(), stmtsp, m_assertp->directive(),
                                        m_assertp->userType(), nodep->vacuous());
            } else {
                stmtsp = newIfAssertFailOn(m_assertp->controlVarp(), stmtsp,
                                           m_assertp->directive(), m_assertp->userType());
            }
        } else if (stmtsp) {
            // The controls apply to attempts starting after them; one already executing is not
            // affected, unless killed (IEEE 1800-2023 20.11). A cover statement controls its
            // own pass action inside, see visitAssertionIterate.
            FileLine* const flp = nodep->fileline();
            const VAssertDirectiveType directive = m_assertp->directive();
            const VAssertType type = m_assertp->userType();
            if (VN_IS(m_assertp, Cover)) {
                for (AstNode* np = stmtsp; np; np = np->nextp()) {
                    AstIf* const ifp = VN_CAST(np, If);
                    if (!ifp || !ifp->user2()) continue;  // Only the assertOn() check
                    pushDeletep(ifp->condp()->unlinkFrBack());
                    ifp->condp(new AstVarRef{
                        flp,
                        getPExprStartVarp("pass0", assertPassOnCond(m_assertp->controlVarp(), flp,
                                                                    type, directive, false)),
                        VAccess::READ});
                }
            }
            AstVar* const enablep
                = nodep->pass()
                      ? getPExprStartVarp(nodep->vacuous() ? "pass1" : "pass0",
                                          assertPassOnCond(m_assertp->controlVarp(), flp, type,
                                                           directive, nodep->vacuous()))
                      : getPExprStartVarp("fail", assertFailOnCond(m_assertp->controlVarp(), flp,
                                                                   type, directive));
            AstVar* const killp = getPExprStartVarp("kill", newKillCountp(flp));
            stmtsp = newQueuedAction(flp, stmtsp);
            stmtsp = newIfControl(new AstVarRef{flp, enablep, VAccess::READ}, stmtsp);
            stmtsp = newIfControl(
                new AstEq{flp, new AstVarRef{flp, killp, VAccess::READ}, newKillCountp(flp)},
                stmtsp);
        }
        if (stmtsp) {
            nodep->replaceWith(stmtsp);
        } else {
            nodep->unlinkFrBack();
        }
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstConstCast* nodep) override {
        // Moved out of its assertion by V3AssertPre; only the expression
        AstNodeExpr* const lhsp = nodep->lhsp()->unlinkFrBack();
        nodep->replaceWith(lhsp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
        iterate(lhsp);
    }
    void visit(AstPExpr* nodep) override {
        if (m_inRestrict) {
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
        } else {
            VL_RESTORER(m_strongPassOnp);
            VL_RESTORER(m_strongFailOnp);
            m_strongPassOnp = nullptr;
            m_strongFailOnp = nullptr;
            const AstCover* const seqCoverp = VN_CAST(m_assertp, Cover);
            if (nodep->finalp() && !nodep->user1() && !(seqCoverp && seqCoverp->isSeqEvent())) {
                FileLine* const flp = nodep->fileline();
                for (AstVar** const varpp : {&m_strongPassOnp, &m_strongFailOnp}) {
                    *varpp = newModuleTemp(flp, m_actionNames.get("StrongOn"),
                                           m_modp->findUInt32DType(), m_modp);
                    (*varpp)->lifetime(VLifetime::STATIC_EXPLICIT);
                }
            }
            {
                VL_RESTORER(m_pexprBodyp);
                VL_RESTORER_CLEAR(m_pexprStartVarps);
                m_pexprBodyp = nodep->bodyp();
                // The waits of the attempt itself: not of action blocks added in its place, which
                // a Kill does not abort once started, nor of other processes in it
                const std::function<void(AstNode*)> findWaits = [&](AstNode* np) {
                    for (; np; np = np->nextp()) {
                        if (VN_IS(np, PExpr) || VN_IS(np, Fork) || VN_IS(np, NodeExpr)) continue;
                        if (VN_IS(np, EventControl) || VN_IS(np, Delay)) np->user3(true);
                        findWaits(np->op1p());
                        findWaits(np->op2p());
                        findWaits(np->op3p());
                        findWaits(np->op4p());
                    }
                };
                // Once, though the PExpr may be visited again
                const bool first = !nodep->user1SetOnce();
                if (first) findWaits(nodep->bodyp()->stmtsp());
                iterateAndNextNull(nodep->bodyp());
                const AstCover* const coverp = VN_CAST(m_assertp, Cover);
                if (first && (!coverp || !coverp->isSeqEvent())) abortWhenKilled(nodep);
            }
            VL_RESTORER(m_inPExprFinal);
            m_inPExprFinal = true;
            iterateAndNextNull(nodep->finalp());
        }
    }

    //========== Statements
    void visit(AstDisplay* nodep) override {
        iterateChildren(nodep);
        // Replace the special types with standard text
        if (nodep->displayType() == VDisplayType::DT_INFO) {
            replaceDisplay(nodep, "-Info");
        } else if (nodep->displayType() == VDisplayType::DT_WARNING) {
            replaceDisplay(nodep, "%%Warning");
        } else if (nodep->displayType() == VDisplayType::DT_ERROR) {
            replaceDisplay(nodep, "%%Error");
        } else if (nodep->displayType() == VDisplayType::DT_FATAL) {
            replaceDisplay(nodep, "%%Fatal");
        } else if (nodep->displayType() == VDisplayType::DT_MONITOR) {
            nodep->displayType(VDisplayType::DT_DISPLAY);
            FileLine* const fl = nodep->fileline();

            const auto monNum = ++m_monitorNum;
            // Where $monitor was we do "__VmonitorNum = N; __VmonitorPending = '1;", so it is
            // displayed when invoked
            AstAssign* const newsetp = new AstAssign{
                fl, newMonitorNumVarRefp(nodep, VAccess::WRITE), new AstConst{fl, monNum}};
            newsetp->addNext(newMonitorPendingSetp(nodep));
            nodep->replaceWith(newsetp);
            // Add "always @(args) if (__VmonitorNum == N) __VmonitorPending = '1;"
            AstSenItem* monSenItemsp = nullptr;
            if (AstNode* const monExprsp = nodep->fmtp()->exprsp()) {
                monExprsp->foreachAndNext([&](AstVarRef* varrefp) {
                    AstSenItem* const senItemp
                        = new AstSenItem{fl, VEdgeType::ET_CHANGED,
                                         // Clone so get VarRef or VarXRef as needed
                                         varrefp->cloneTree(false)};
                    monSenItemsp = AstNode::addNextNull(monSenItemsp, senItemp);
                });
            }
            if (monSenItemsp) {
                AstNodeExpr* const activep = new AstEq{fl, new AstConst{fl, monNum},
                                                       newMonitorNumVarRefp(nodep, VAccess::READ)};
                AstIf* const setIfp = new AstIf{fl, activep, newMonitorPendingSetp(nodep)};
                AstSenTree* const monSenTreep = new AstSenTree{fl, monSenItemsp};
                m_modp->addStmtsp(new AstAlways{fl, VAlwaysKwd::ALWAYS, monSenTreep, setIfp});
            }
            // Display once at the end of the time step (IEEE 1800-2023 21.2.3), like $strobe:
            // "always_postponed if (__VmonitorPending && __VmonitorNum == N) begin
            //    __VmonitorPending = '0; if (!__VmonitorOff) $display(...); end"
            AstNodeExpr* const pendingp
                = new AstLogAnd{fl, newMonitorPendingVarRefp(nodep, VAccess::READ),
                                new AstEq{fl, new AstConst{fl, monNum},
                                          newMonitorNumVarRefp(nodep, VAccess::READ)}};
            AstNodeExpr* const onp = new AstLogNot{fl, newMonitorOffVarRefp(nodep, VAccess::READ)};
            AstIf* const onIfp = new AstIf{fl, onp, nodep};
            onIfp->isBoundsCheck(true);  // To avoid LATCH warning
            AstAssign* const clearp
                = new AstAssign{fl, newMonitorPendingVarRefp(nodep, VAccess::WRITE),
                                new AstConst{fl, AstConst::BitFalse{}}};
            AstIf* const ifp = new AstIf{fl, pendingp, clearp};
            ifp->addThensp(onIfp);
            ifp->isBoundsCheck(true);  // To avoid LATCH warning
            ifp->branchPred(VBranchPred::BP_UNLIKELY);
            m_modp->addStmtsp(new AstAlwaysPostponed{fl, ifp});
        } else if (nodep->displayType() == VDisplayType::DT_STROBE) {
            nodep->displayType(VDisplayType::DT_DISPLAY);
            // Need one-shot
            FileLine* const fl = nodep->fileline();
            AstVar* const varp
                = new AstVar{fl, VVarType::MODULETEMP, "__Vstrobe" + cvtToStr(m_modStrobeNum++),
                             nodep->findBitDType()};
            m_modp->addStmtsp(varp);
            // Where $strobe was we do "__Vstrobe = '1;"
            AstAssign* const newsetp = new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                                     new AstConst{fl, AstConst::BitTrue{}}};
            nodep->replaceWith(newsetp);
            // Add "always_comb if (__Vstrobe) begin $display(...); __Vstrobe = '0; end"
            AstNodeStmt* const stmtsp = nodep;
            AstIf* const ifp = new AstIf{fl, new AstVarRef{fl, varp, VAccess::READ}, stmtsp};
            ifp->isBoundsCheck(true);  // To avoid LATCH warning
            ifp->branchPred(VBranchPred::BP_UNLIKELY);
            AstNode* const newp = new AstAlwaysPostponed{fl, ifp};
            stmtsp->addNext(new AstAssign{fl, new AstVarRef{fl, varp, VAccess::WRITE},
                                          new AstConst{fl, AstConst::BitFalse{}}});
            m_modp->addStmtsp(newp);
        }
    }
    void visit(AstMonitorOff* nodep) override {
        FileLine* const flp = nodep->fileline();
        AstAssign* const newp
            = new AstAssign{flp, newMonitorOffVarRefp(nodep, VAccess::WRITE),
                            new AstConst{flp, AstConst::BitTrue{}, nodep->off()}};
        // $monitoron displays immediately (IEEE 1800-2023 21.2.3)
        if (!nodep->off()) newp->addNext(newMonitorPendingSetp(nodep));
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstEventControl* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstWait* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstWaitFork* nodep) override {
        iterateChildren(nodep);
        m_obsWaitsp.push_back(nodep);
    }
    void visit(AstDisableTargetBody* nodep) override {
        iterateChildren(nodep);
        // V3LinkJump wraps only the body of a process's outermost scope. Running to its end
        // means the scope was not disabled.
        if (m_obsFlushp) {
            FileLine* const flp = nodep->fileline();
            m_obsDoneVarp
                = newModuleTemp(flp, m_obsNames.get("Done"), m_modp->findBitDType(), m_modp);
            m_obsDoneVarp->setIgnoreSchedWrite();
            nodep->addStmtsp(new AstAssign{flp, new AstVarRef{flp, m_obsDoneVarp, VAccess::WRITE},
                                           new AstConst{flp, AstConst::BitTrue{}}});
        }
        UASSERT_OBJ(nodep->stmtsp(), nodep, "V3LinkJump wraps only a non-empty body");
        nodep->addNextHere(nodep->stmtsp()->unlinkFrBackWithNext());
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }
    void visit(AstFork* nodep) override {
        iterateAndNextNull(nodep->declsp());
        iterateAndNextNull(nodep->stmtsp());
        VL_RESTORER(m_inSpawnedFork);
        m_inSpawnedFork |= !nodep->joinType().join();
        for (AstForkItem* const branchp : nodep->forkspList()) {
            // V3LinkJump's wrapper runs part of the enclosing process
            if (branchp->disableWrapper()) {
                iterate(branchp);
                continue;
            }
            // IEEE 1800-2023 9.3.2: Each branch is a separate process
            VL_RESTORER(m_inForkBranch);
            m_inForkBranch = true;
            VL_RESTORER(m_obsFlushp);
            VL_RESTORER(m_obsDoneVarp);
            VL_RESTORER_CLEAR(m_obsWaitsp);
            m_obsFlushp = nullptr;
            m_obsDoneVarp = nullptr;
            iterate(branchp);
            addObsFlushes(branchp);
        }
    }
    void visit(AstAssert* nodep) override {  //
        visitAssertionIterate(nodep, nodep->failsp());
    }
    AstVar* newControlArgp(AstNodeExpr* exprp, AstBegin* beginp) {
        AstVar* const varp
            = new AstVar{exprp->fileline(), VVarType::BLOCKTEMP,
                         "__VassertCtlArg" + std::to_string(m_controlTempNum++), exprp->dtypep()};
        if (m_ftaskp) {
            varp->funcLocal(true);
            varp->lifetime(VLifetime::AUTOMATIC_EXPLICIT);
            m_ftaskp->addDeclsp(varp);
        } else {
            // Procedural operands execute without yielding. Module-owned storage
            // must not pretend to be an automatic enclosing-fork variable.
            varp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(varp);
        }
        beginp->addStmtsp(new AstAssign{
            exprp->fileline(), new AstVarRef{exprp->fileline(), varp, VAccess::WRITE}, exprp});
        return varp;
    }
    static AstCStmt* newControlCallp(FileLine* flp, AstVar* controlp, AstVar* typesp,
                                     VAssertDirectiveType directives, AstNodeVarRef* statep) {
        AstCStmt* const stmtp
            = new AstCStmt{flp, statep ? "vlSymsp->_vm_contextp__->assertCtlApply("
                                       : "vlSymsp->_vm_contextp__->assertCtl("};
        stmtp->add(new AstVarRef{flp, controlp, VAccess::READ});
        stmtp->add(", ");
        stmtp->add(new AstVarRef{flp, typesp, VAccess::READ});
        stmtp->add(", " + std::to_string(directives));
        if (statep) {
            stmtp->add(", ");
            stmtp->add(statep);
        }
        stmtp->add(");\n");
        return stmtp;
    }
    static AstConst* newControlLevelConstp(FileLine* flp, AstVar* levelp, uint32_t value) {
        AstConst* const constp = new AstConst{flp, AstConst::DTyped{}, levelp->dtypep()};
        constp->num().setLong(value);
        return constp;
    }
    AstNodeStmt* newScopedControlp(AstAssertCtl* nodep) {
        FileLine* const flp = nodep->fileline();
        AstAssertCtlArgs* const argsp = nodep->argsp();
        AstBegin* const beginp = new AstBegin{flp, "", nullptr, true};
        // Evaluate effect operands once, in source order, even for an empty selection.
        AstVar* const controlp = newControlArgp(nodep->controlTypep()->unlinkFrBack(), beginp);
        AstVar* const typesp
            = newControlArgp(nodep->assertTypesp() ? nodep->assertTypesp()->unlinkFrBack()
                                                   : new AstConst{flp, ALL_ASSERT_TYPES},
                             beginp);
        AstNodeExpr* levelExprp
            = argsp->levelp() ? argsp->levelp()->unlinkFrBack() : new AstConst{flp, 0};
        const bool signedLevel = levelExprp->isSigned();
        // Widen narrow levels so a compiler-derived depth cannot truncate to that width.
        // Wider integer expressions retain their complete value.
        if (levelExprp->width() < 32) {
            levelExprp = signedLevel
                             ? static_cast<AstNodeExpr*>(new AstExtendS{flp, levelExprp, 32})
                             : static_cast<AstNodeExpr*>(new AstExtend{flp, levelExprp, 32});
        }
        AstVar* const levelp = newControlArgp(levelExprp, beginp);
        AstNodeStmt* selectedp = nullptr;
        for (AstAssertCtlTarget* const targetp : argsp->targetspList()) {
            AstCStmt* const callp = newControlCallp(flp, controlp, typesp, nodep->directiveTypes(),
                                                    targetp->statep()->unlinkFrBack());
            AstNodeExpr* const depthp
                = newControlLevelConstp(flp, levelp, static_cast<uint32_t>(targetp->depth()));
            AstNodeExpr* const beyondp
                = signedLevel
                      ? static_cast<AstNodeExpr*>(
                            new AstGtS{flp, new AstVarRef{flp, levelp, VAccess::READ}, depthp})
                      : static_cast<AstNodeExpr*>(
                            new AstGt{flp, new AstVarRef{flp, levelp, VAccess::READ}, depthp});
            AstNodeExpr* const levelCondp
                = new AstLogOr{flp,
                               new AstEq{flp, new AstVarRef{flp, levelp, VAccess::READ},
                                         newControlLevelConstp(flp, levelp, 0)},
                               beyondp};
            selectedp = AstNode::addNextNull(selectedp, new AstIf{flp, levelCondp, callp});
        }
        AstCExpr* const validp = new AstCExpr{flp, "vlSymsp->_vm_contextp__->assertCtlValid(", 1};
        validp->add(new AstVarRef{flp, controlp, VAccess::READ});
        validp->add(")");
        // Validate once before applying any selected site, including no selected
        // sites. The global zero-level route already performs this validation.
        AstIf* const validatedp = new AstIf{flp, validp, selectedp};
        if (argsp->scoped()) {
            beginp->addStmtsp(validatedp);
        } else {
            // With no scope list, zero levels preserves the context-wide control API.
            beginp->addStmtsp(
                new AstIf{flp,
                          new AstEq{flp, new AstVarRef{flp, levelp, VAccess::READ},
                                    newControlLevelConstp(flp, levelp, 0)},
                          newControlCallp(flp, controlp, typesp, nodep->directiveTypes(), nullptr),
                          validatedp});
        }
        return beginp;
    }
    void visit(AstAssertCtl* nodep) override {
        iterateChildren(nodep);

        bool assertTypeConst = true;
        if (!nodep->assertTypesp()) {
            nodep->assertTypes(VAssertType{ALL_ASSERT_TYPES});
        } else if (const AstConst* const assertTypesp = VN_CAST(nodep->assertTypesp(), Const)) {
            nodep->assertTypes(VAssertType{assertTypesp->toSInt()});
        } else {
            assertTypeConst = false;
        }

        bool controlTypeConst = false;
        if (const AstConst* const constp = VN_CAST(nodep->controlTypep(), Const)) {
            nodep->ctlType(constp->toSInt());
            controlTypeConst = true;
        }
        if (controlTypeConst
            && (nodep->ctlType() < VAssertCtlType::LOCK
                || nodep->ctlType() > VAssertCtlType::VACUOUS_OFF)) {
            nodep->unlinkFrBack();
            nodep->v3error("Bad $assertcontrol control_type '"
                           << cvtToStr(static_cast<int>(nodep->ctlType()))
                           << "' (IEEE 1800-2023 Table 20-5)");
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        if (assertTypeConst && nodep->assertTypes() != ALL_ASSERT_TYPES
            && nodep->assertTypes().containsAny(VAssertType::UNIQUE | VAssertType::UNIQUE0
                                                | VAssertType::PRIORITY)
            && (!controlTypeConst || nodep->ctlType() > VAssertCtlType::KILL)) {
            // Violation checks are only enabled by the On/Off state; pass and fail action
            // controls would be silently ignored
            nodep->v3warn(E_UNSUPPORTED, "Unsupported: assert control of unique, unique0 or"
                                         " priority checks with this control_type");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }
        bool directiveTypeConst = true;
        if (!nodep->directiveTypesp()) {
            nodep->directiveTypes(VAssertDirectiveType::ASSERT | VAssertDirectiveType::ASSUME
                                  | VAssertDirectiveType::COVER);
        } else if (const AstConst* const directiveTypesp
                   = VN_CAST(nodep->directiveTypesp(), Const)) {
            nodep->directiveTypes(VAssertDirectiveType{directiveTypesp->toSInt()});
        } else {
            directiveTypeConst = false;
        }
        if (!directiveTypeConst) {
            nodep->v3warn(E_UNSUPPORTED,
                          "Unsupported: non-const assert directive type expression");
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
            return;
        }

        if (nodep->argsp()) {
            nodep->replaceWith(newScopedControlp(nodep));
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        FileLine* const fl = nodep->fileline();
        UINFO(9, "Generating assertctl for a module: " << m_modp);
        AstCStmt* const newp = new AstCStmt{fl};
        newp->add("vlSymsp->_vm_contextp__->assertCtl(");
        newp->add(nodep->controlTypep()->unlinkFrBack());
        newp->add(", ");
        if (nodep->assertTypesp()) {
            newp->add(nodep->assertTypesp()->unlinkFrBack());
        } else {
            newp->add(std::to_string(ALL_ASSERT_TYPES));
        }
        newp->add(", " + std::to_string(nodep->directiveTypes()) + ");\n");
        nodep->replaceWith(newp);
        VL_DO_DANGLING(pushDeletep(nodep), nodep);
    }
    void visit(AstAssertIntrinsic* nodep) override {  //
        visitAssertionIterate(nodep, nodep->failsp());
    }
    void visit(AstCover* nodep) override {  //
        visitAssertionIterate(nodep, nullptr);
    }
    void visit(AstRestrict* nodep) override {
        VL_RESTORER(m_inRestrict);
        m_inRestrict = true;
        iterateChildren(nodep);
        // IEEE says simulator ignores these
        VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
    }

    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER(m_controlTempNum);
        m_controlTempNum = 0;
        VL_RESTORER_COPY(m_obsNames);
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsEventp);
        VL_RESTORER(m_obsReactivep);
        VL_RESTORER_COPY(m_actionNames);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER(m_modPastNum);
        VL_RESTORER(m_modStrobeNum);
        VL_RESTORER(m_finalp);
        VL_RESTORER_CLEAR(m_modExpr2Sen2DelayedAlwaysp);
        VL_RESTORER_CLEAR(m_modExpr2Sen2DefaultDelayedAlwaysp);
        VL_RESTORER_CLEAR(m_delayedAlways2TickTimep);
        m_modp = nodep;
        m_modPastNum = 0;
        m_obsNames.reset();
        m_obsFlushp = nullptr;
        m_obsEventp = nullptr;
        m_obsReactivep = nullptr;
        m_actionNames.reset();
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        m_modStrobeNum = 0;
        m_finalp = nullptr;
        iterateChildren(nodep);
    }
    void visit(AstAlways* nodep) override {
        if (nodep->keyword() != VAlwaysKwd::ASSERT_COVER) {
            visit(static_cast<AstNodeProcedure*>(nodep));
            return;
        }
        // The process of a concurrent assertion, not a procedural context. The assertion clocks
        // it, or it goes with the assertion.
        VL_RESTORER(m_assertCoverp);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER_CLEAR(m_namedBeginps);
        m_assertCoverp = nodep;
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        iterateChildren(nodep);
        if (nodep->keyword() == VAlwaysKwd::ASSERT_COVER) {
            VL_DO_DANGLING(pushDeletep(nodep->unlinkFrBack()), nodep);
        }
    }
    void visit(AstNodeProcedure* nodep) override {
        VL_RESTORER(m_procedurep);
        VL_RESTORER(m_matureEpochp);
        m_matureEpochp = nullptr;
        VL_RESTORER(m_obsFlushp);
        VL_RESTORER(m_obsDoneVarp);
        VL_RESTORER_CLEAR(m_obsWaitsp);
        VL_RESTORER(m_actionEventp);
        VL_RESTORER(m_actionReactivep);
        VL_RESTORER_CLEAR(m_namedBeginps);
        m_procedurep = nodep;
        m_actionEventp = nullptr;
        m_actionReactivep = nullptr;
        AstBegin* const scopep = VN_CAST(nodep->stmtsp(), Begin);
        iterateChildren(nodep);
        // IEEE 1800-2023 16.4.2: The process resumes from its event control, or was declared by
        // an always_comb or always_latch and is resumed due to a transition on one of its
        // dependent signals.
        if (AstAlways* const alwaysp = VN_CAST(nodep, Always)) {
            if (alwaysp->stmtsp()
                && (alwaysp->sentreep() || alwaysp->keyword() == VAlwaysKwd::ALWAYS_COMB
                    || alwaysp->keyword() == VAlwaysKwd::ALWAYS_LATCH)) {
                addResumeFlush(alwaysp);
            }
        }
        addObsFlushes(scopep);
    }
    void visit(AstNodeFTask* nodep) override {
        VL_RESTORER(m_ftaskp);
        VL_RESTORER(m_obsFlushp);
        m_ftaskp = nodep;
        m_obsFlushp = nullptr;
        iterateChildren(nodep);
    }
    void visit(AstGenBlock* nodep) override {
        // This code is needed rather than a visitor in V3Begin,
        // because V3Assert is called before V3Begin
        VL_RESTORER(m_beginp);
        m_beginp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstBegin* nodep) override {
        // This code is needed rather than a visitor in V3Begin,
        // because V3Assert is called before V3Begin
        VL_RESTORER(m_beginp);
        m_beginp = nodep;
        if (!nodep->name().empty()) m_namedBeginps.push_back(nodep);
        iterateChildren(nodep);
        if (!nodep->name().empty()) m_namedBeginps.pop_back();
        // If the body is a single assertOn check, bubble it up for combining
        if (!nodep->declsp()) {
            if (AstIf* const ifp = VN_CAST(nodep->stmtsp(), If)) {
                if (ifp->user2() && !ifp->nextp()) {
                    ++m_statAssertOnHoisted;
                    nodep->replaceWith(ifp->unlinkFrBack());
                    nodep->addStmtsp(ifp->thensp()->unlinkFrBackWithNext());
                    ifp->addThensp(nodep);
                }
            }
        }
    }

    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~AssertVisitor() override {
        V3Stats::addStat("Assertions, assert non-immediate statements", m_statAsNotImm);
        V3Stats::addStat("Assertions, assert immediate statements", m_statAsImm);
        V3Stats::addStat("Assertions, cover statements", m_statCover);
        V3Stats::addStat("Assertions, full/parallel case", m_statAsFull);
        V3Stats::addStat("Assertions, $past variables", m_statPastVars);
        V3Stats::addStat("Assertions, assertOn checks combined", m_statAssertOnCombined);
        V3Stats::addStat("Assertions, assertOn checks hoisted", m_statAssertOnHoisted);
        V3Stats::addStat("Assertions, lifted impure case expressions", m_statLiftedCaseExprs);
        // Rewrites can change purity, e.g. by compiling out assertion statements with --no-assert
        VIsCached::clearCacheTree();
    }
};

//######################################################################
// Top Assert class

void V3Assert::assertAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { AssertVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("assert", 0, dumpTreeEitherLevel() >= 3);
}
