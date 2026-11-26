// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
// DESCRIPTION: Verilator: Inline SVA property and sequence instances
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
// V3AssertElab's Transformations:
//
//  Runs after V3Width and before V3WidthCommit, so that V3WidthCommit checks
//  each inlined body in the context of its instance, e.g. that a function
//  holds no cycle delay (IEEE 1800-2023 13.4).
//  - Lower a sequence used as an event control into a cover sequence firing
//    a synthesized event (IEEE 1800-2023 9.4.2.4), so its instance is
//    inlined like the others.
//  - Replace a property instance forming a whole property spec with the
//    property body (IEEE 1800-2023 16.12.1). The local variables of each
//    property or sequence instance become module temporaries
//    (IEEE 1800-2023 16.10).
//  - Replace a property instance nested in an expression with the expression
//    of the property body. A body with a disable condition, a clocking event
//    or a multi-cycle operator is reported instead.
//  - Replace each sequence instance with the sequence body
//    (IEEE 1800-2023 16.8).
//  Actual arguments are substituted for formal arguments (IEEE 1800-2023 F.4.1),
//  then the cycle delays of the body are checked.
//  Property and sequence declarations are kept, as V3Undriven lints the
//  variables they declare and read. V3AssertPre removes them.
//
//  A sequence or property instance anywhere but in the property expression of
//  an assertion is reported as illegal, as sequence event controls are already
//  lowered.
//  Instances in a restrict property are not inlined either, as V3AssertNfa
//  removes it.
//  Inlined bodies keep their declaration lines with coverage off, as
//  V3Coverage does not cover declarations.
//  The body of a property instance that is itself a property instance is
//  marked as an instance chain, which V3AssertNfa leaves to V3AssertPre.
//
//*************************************************************************

#include "V3PchAstNoMT.h"  // VL_MT_DISABLED_CODE_UNIT

#include "V3AssertElab.h"

#include "V3Assert.h"
#include "V3Const.h"
#include "V3LinkLValue.h"
#include "V3Stats.h"
#include "V3Task.h"
#include "V3UniqueNames.h"

#include <unordered_map>
#include <vector>

VL_DEFINE_DEBUG_FUNCTIONS;

//######################################################################

// Lower a sequence used as an event control ('@seq', IEEE 1800-2023 9.4.2.4) into a
// synthesized event fired by an internal 'cover sequence' on each end-of-match
class SeqEventLowerVisitor final : public VNVisitor {
    // STATE
    AstNodeModule* m_modp = nullptr;  // Current module
    V3UniqueNames m_names{"__VseqEvent"};  // Synthesized event names

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        m_modp = nodep;
        iterateChildren(nodep);
    }
    void visit(AstSenItem* nodep) override {
        AstSchemaRef* const schemaRefp = VN_CAST(nodep->sensp(), SchemaRef);
        if (schemaRefp && VN_IS(schemaRefp->schemap(), Sequence)) {
            FileLine* const flp = nodep->fileline();
            const AstNodeVarRef* automaticRefp = nullptr;
            schemaRefp->exists([&](const AstNodeVarRef* refp) {
                if (!refp->varp()->lifetime().isAutomatic()) return false;
                automaticRefp = refp;
                return true;
            });
            if (automaticRefp) {
                automaticRefp->v3error("Arguments to a sequence used as an event control must be"
                                       " static (IEEE 1800-2023 9.4.2.4)");
                schemaRefp->replaceWith(new AstConst{flp, AstConst::BitFalse{}});
                VL_DO_DANGLING(pushDeletep(schemaRefp), schemaRefp);
                return;
            }
            schemaRefp->unlinkFrBack();
            AstVar* const eventp
                = V3AssertCommon::newSequenceEvent(flp, m_modp, m_names.get(nodep), schemaRefp);
            nodep->sensp(new AstVarRef{flp, eventp, VAccess::READ});
            return;
        }
        iterateChildren(nodep);
    }
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    explicit SeqEventLowerVisitor(AstNetlist* nodep) { iterate(nodep); }
};

//######################################################################

class AssertElabVisitor final : public VNVisitor {
    // STATE
    AstNodeModule* m_modp = nullptr;  // Current module
    // In the property expression of an assertion, the only place left where a sequence or
    // property instance is legal, as SeqEventLowerVisitor lowered the sequence event controls
    bool m_inPropExpr = false;
    bool m_inDisable = false;  // In a disable condition
    V3UniqueNames m_propVarNames{"__Vpropvar"};  // Property-local variable names
    // Declaration file line -> its copy with coverage off, for inlined bodies
    std::unordered_map<FileLine*, FileLine*> m_noCoverFileLines;
    VDouble0 m_statPropInlined;  // Statistic tracking
    VDouble0 m_statSeqInlined;  // Statistic tracking

    // METHODS
    // Fold and validate ranged eventually bounds after substituting property arguments.
    static bool checkSvaEventuallyBounds(AstEventually* nodep) {
        const int errorsBefore = V3Error::errorCount();
        V3Const::constifyParamsEdit(nodep->loBoundp());
        if (!VN_IS(nodep->hiBoundp(), Unbounded)) V3Const::constifyParamsEdit(nodep->hiBoundp());
        if (V3Error::errorCount() != errorsBefore) return false;
        const bool hiUnbounded = VN_IS(nodep->hiBoundp(), Unbounded);
        if (!nodep->isStrong() && hiUnbounded) {
            nodep->v3error("The range for a weak eventually must be bounded (IEEE "
                           "1800-2023 16.12.13)");
            return false;
        }
        const AstConst* const loConstp = VN_CAST(nodep->loBoundp(), Const);
        const AstConst* const hiConstp = VN_CAST(nodep->hiBoundp(), Const);

        if (!loConstp || loConstp->num().isOpaque()) {
            nodep->loBoundp()->v3error(nodep->verilogKwd() << " range low bound must be integral"
                                                              " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if (loConstp->num().isFourState()) {
            loConstp->v3error(nodep->verilogKwd() << " range low bound cannot contain X or Z"
                                                     " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if (loConstp->dtypep()->isSigned() && loConstp->num().isNegative()) {
            loConstp->v3error(nodep->verilogKwd() << " range low bound must be non-negative"
                                                     " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if (!V3AssertCommon::checkSvaValueLimit(
                nodep, loConstp, (nodep->verilogKwd() + " range low bound value").c_str())) {
            return false;
        }
        if (hiUnbounded) return true;

        if (!hiConstp || hiConstp->num().isOpaque()) {
            nodep->hiBoundp()->v3error(nodep->verilogKwd() << " range high bound must be integral"
                                                              " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if (hiConstp->num().isFourState()) {
            hiConstp->v3error(nodep->verilogKwd() << " range high bound cannot contain X or Z"
                                                     " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if ((hiConstp->dtypep()->isSigned() && hiConstp->num().isNegative())
            || hiConstp->num().isLt(loConstp->num())) {
            hiConstp->v3error(nodep->verilogKwd() << " range high bound must be >= low bound"
                                                     " (IEEE 1800-2023 16.12.13)");
            return false;
        }
        if (!V3AssertCommon::checkSvaValueLimit(
                nodep, hiConstp, (nodep->verilogKwd() + " range high bound value").c_str())) {
            return false;
        }
        return true;
    }
    // The property instantiated as the whole of specp, if any
    static const AstProperty* instancedProperty(const AstPropSpec* specp) {
        const AstSchemaRef* const schemaRefp = VN_CAST(specp->propp(), SchemaRef);
        return schemaRefp ? VN_CAST(schemaRefp->schemap(), Property) : nullptr;
    }
    // Copy of a declaration file line with coverage off, shared by all inlined copies
    FileLine* noCoverFileLine(FileLine* flp) {
        FileLine*& copyp = m_noCoverFileLines[flp];
        if (!copyp) {
            copyp = new FileLine{flp};
            copyp->coverageOn(false);
        }
        return copyp;
    }
    // Turn coverage off on the file lines of a subtree.
    void coverageOff(AstNode* nodep) {
        nodep->foreach([&](AstNode* np) { np->fileline(noCoverFileLine(np->fileline())); });
    }
    // Check the cycle delays, repetition counts, always ranges and $past tick counts of a
    // sequence or property instance, after its formal arguments are replaced with the actual
    // arguments (IEEE 1800-2023 16.8), reporting errors on instp
    static void checkInstanceConstants(AstNode* nodep, AstNode* instp) {
        // Collect first, as checking edits them
        std::vector<AstDelay*> delayps;
        nodep->foreach([&](AstDelay* delayp) { delayps.push_back(delayp); });
        for (AstDelay* const delayp : delayps) V3AssertCommon::checkSvaCycleDelay(delayp, instp);
        std::vector<AstNodeExpr*> exprps;
        nodep->foreach([&](AstNodeExpr* exprp) {
            const AstPast* const pastp = VN_CAST(exprp, Past);
            if (VN_IS(exprp, SConsRep) || VN_IS(exprp, SGotoRep) || VN_IS(exprp, SNonConsRep)
                || VN_IS(exprp, PropAlways) || (pastp && pastp->ticksp())) {
                exprps.push_back(exprp);
            }
        });
        // Inner ones first, as checking an outer one may delete an invalid count holding them
        for (auto it = exprps.rbegin(); it != exprps.rend(); ++it) {
            AstNodeExpr* const exprp = *it;
            if (AstSConsRep* const repp = VN_CAST(exprp, SConsRep)) {
                V3AssertCommon::checkSvaRepetition(repp, instp);
            } else if (AstSGotoRep* const repp = VN_CAST(exprp, SGotoRep)) {
                V3AssertCommon::checkSvaRepetition(repp, instp);
            } else if (AstSNonConsRep* const repp = VN_CAST(exprp, SNonConsRep)) {
                V3AssertCommon::checkSvaRepetition(repp, instp);
            } else if (AstPropAlways* const alwaysp = VN_CAST(exprp, PropAlways)) {
                V3AssertCommon::checkSvaAlwaysRange(alwaysp, instp);
            } else {
                V3AssertCommon::checkSvaPastTicks(VN_AS(exprp, Past), instp);
            }
        }
    }
    // Replace formal argument references under bodyp with the actual arguments of schemaRefp,
    // and retarget property-local variable references per localVarMap
    // Substitute the actual arguments into bodyp, returning the possibly replaced body
    AstNode* substituteArgs(AstNode* bodyp, AstSchemaRef* schemaRefp,
                            const std::unordered_map<const AstVar*, AstVar*>& localVarMap) {
        const V3TaskConnects tconnects = V3Task::taskConnects(schemaRefp);
        std::unordered_map<const AstVar*, AstNodeExpr*> portMap;
        for (const auto& tconnect : tconnects) {
            portMap[tconnect.first] = tconnect.second->exprp();
        }
        bodyp = V3AssertCommon::checkSvaUnboundedActuals(bodyp, portMap, schemaRefp);
        // A body that is only a formal argument is replaced as a whole, as the root of the
        // clone cannot be replaced in place
        if (const AstVarRef* const refp = VN_CAST(bodyp, VarRef)) {
            const auto it = portMap.find(refp->varp());
            if (it != portMap.end()) {
                VL_DO_DANGLING(bodyp->deleteTree(), bodyp);
                bodyp = it->second->cloneTree(false);
            }
        }
        std::vector<AstNodeExpr*> actualps;
        bodyp->foreach([&](AstVarRef* refp) {
            const auto portIt = portMap.find(refp->varp());
            if (portIt != portMap.end()) {
                AstNodeExpr* const actualp = portIt->second->cloneTree(false);
                actualps.push_back(actualp);
                // An assigned formal makes the actual an lvalue
                if (refp->access().isWriteOrRW()) {
                    V3LinkLValue::linkLValueSet(actualp, refp->access());
                }
                refp->replaceWith(actualp);
                VL_DO_DANGLING(pushDeletep(refp), refp);
                return;
            }
            const auto localIt = localVarMap.find(refp->varp());
            if (localIt != localVarMap.end()) refp->varp(localIt->second);
        });  // LCOV_EXCL_LINE -- gcov attributes lambda's implicit return to `})`
        V3AssertCommon::removeActualReductions(actualps);
        // Constants with a formal argument are checked once it is substituted
        checkInstanceConstants(bodyp, schemaRefp);
        return bodyp;
    }
    // Promote the local variables of an instance of a property or sequence to module-level
    // temps, returning each declared variable's temp (IEEE 1800-2023 16.10)
    std::unordered_map<const AstVar*, AstVar*>
    promoteLocalVars(const AstNodeSchema* const schemap) {
        std::unordered_map<const AstVar*, AstVar*> localVarMap;
        for (const AstNode* const declp : schemap->declspList()) {
            // Declarations also hold typedefs of inline types, see V3LinkParse
            const AstVar* const varp = VN_CAST(declp, Var);
            if (!varp || varp->isIO()) continue;
            // V3Undriven checks the declared variable, not its per-instance copies
            FileLine* const flp = new FileLine{noCoverFileLine(varp->fileline())};
            flp->modifyWarnOff(V3ErrorCode::UNDRIVEN, true);
            flp->modifyWarnOff(V3ErrorCode::UNUSEDSIGNAL, true);
            // An XTEMP stays one, see isMatchItem in V3AssertNfa
            const VVarType varType
                = varp->varType() == VVarType::XTEMP ? VVarType::XTEMP : VVarType::MODULETEMP;
            AstVar* const newVarp
                = new AstVar{flp, varType, m_propVarNames.get(varp), varp->dtypep()};
            newVarp->origName(varp->origName());  // For diagnostics
            newVarp->isAssertLocal(!varp->isTemp());
            newVarp->lifetime(VLifetime::STATIC_EXPLICIT);
            m_modp->addStmtsp(newVarp);
            localVarMap[varp] = newVarp;
        }
        return localVarMap;
    }
    // Clone the body of a property instance, with the actual arguments substituted
    AstPropSpec* cloneProperty(AstSchemaRef* schemaRefp, AstProperty* propp) {
        AstPropSpec* const specp = VN_AS(
            V3AssertCommon::relinkSvaInstanceBody(propp->specp()->cloneTree(false), schemaRefp),
            PropSpec);
        coverageOff(specp);
        const std::unordered_map<const AstVar*, AstVar*> localVarMap = promoteLocalVars(propp);
        substituteArgs(specp, schemaRefp, localVarMap);
        V3AssertCommon::lowerSvaLocalVarInits(propp, specp, localVarMap);
        ++m_statPropInlined;
        return specp;
    }
    void inlineProperty(AstPropSpec* outerSpecp, AstSchemaRef* schemaRefp,
                        AstProperty* propp) {
        AstPropSpec* const propSpecp = cloneProperty(schemaRefp, propp);
        if (outerSpecp->fromInstanceChain() || instancedProperty(propSpecp)) {
            propSpecp->fromInstanceChain(true);
        }

        // Merge disable iff (IEEE 1800-2023 16.12.1)
        if (outerSpecp->disablep() && propSpecp->disablep()) {
            outerSpecp->v3error("disable iff expression before property call "
                                "and in its body is not legal");
            pushDeletep(propSpecp->disablep()->unlinkFrBack());
        }
        if (outerSpecp->disablep()) propSpecp->disablep(outerSpecp->disablep()->unlinkFrBack());

        if (outerSpecp->sensesp() && propSpecp->sensesp()) {
            outerSpecp->v3warn(E_UNSUPPORTED,
                               "Unsupported: Clock event before property call and in its body");
            pushDeletep(propSpecp->sensesp()->unlinkFrBackWithNext());
        }
        if (outerSpecp->sensesp()) {
            propSpecp->addSensesp(outerSpecp->sensesp()->unlinkFrBackWithNext());
        }

        outerSpecp->replaceWith(propSpecp);
        VL_DO_DANGLING(pushDeletep(outerSpecp), outerSpecp);
        // Only as the whole property of an assertion, not of another property
        if (VN_IS(propSpecp->backp(), NodeCoverOrAssert)) {
            V3AssertCommon::reducePlainAlways(propSpecp);
        }
    }
    // True if an actual argument of schemaRefp contains a property instance
    static bool hasPropertyArg(const AstSchemaRef* schemaRefp) {
        // Such an instance would be substituted for an untyped formal, which V3Width typed as a
        // boolean.
        return schemaRefp->argsp()
               && schemaRefp->argsp()->existsAndNext(
                   [](const AstSchemaRef* refp) { return VN_IS(refp->schemap(), Property); });
    }
    // True if nodep is within an operand of a sequence operator or an implication antecedent
    static bool isUnderSequenceOperator(const AstNode* nodep) {
        for (const AstNode *belowp = nodep, *abovep = nodep->aboveLoopp(); VN_IS(abovep, NodeExpr);
             belowp = abovep, abovep = abovep->aboveLoopp()) {
            if (VN_IS(abovep, SExpr) || VN_IS(abovep, SConsRep) || VN_IS(abovep, SGotoRep)
                || VN_IS(abovep, SNonConsRep) || VN_IS(abovep, SIntersect)
                || VN_IS(abovep, SWithin) || VN_IS(abovep, SThroughout)) {
                return true;
            }
            const AstImplication* const implp = VN_CAST(abovep, Implication);
            if (implp && implp->lhsp() == belowp) return true;
        }
        return false;
    }
    // True if the multi-cycle body specp of a nested property instance can replace it, as the
    // NFA lowers it like the equivalent inline property (IEEE 1800-2023 16.12.1). A body with a
    // strength is not a plain operand, and a property instance is not a sequence operand
    // (IEEE 1800-2023 A.2.10). Nor is a body with a match item, as its local variables would only
    // be lowered at the top level of the property.
    static bool isInlinableMultiCycle(const AstSchemaRef* schemaRefp, const AstPropSpec* specp) {
        return specp->propStrength() == VPropStrength::DEFAULT && !hasPropertyArg(schemaRefp)
               && !isUnderSequenceOperator(schemaRefp)
               && !specp->exists([](const AstExprStmt*) { return true; })
               && !isAlwaysOverPropertyOps(specp);
    }
    // True if a property body is an 'always' of a property, only supported as a whole property
    static bool isAlwaysOverPropertyOps(const AstPropSpec* specp) {
        // As V3Width reports for the same property written out (IEEE 1800-2023 16.12.11)
        const AstPropAlways* const alwaysp = VN_CAST(specp->propp(), PropAlways);
        return alwaysp && alwaysp->propp()->exists([](const AstNode* np) {
            const AstNodeExpr* const exprp = VN_CAST(np, NodeExpr);
            return (exprp && exprp->isMultiCycleSva()) || VN_IS(np, Implication)
                   || VN_IS(np, Until) || VN_IS(np, PropSpec);
        });
    }
    void inlineNestedProperty(AstSchemaRef* schemaRefp, AstProperty* propp) {
        AstPropSpec* const specp = cloneProperty(schemaRefp, propp);
        AstNode* replp = nullptr;
        if (specp->disablep()) {
            schemaRefp->v3error("Illegal 'disable iff' in a nested property instance"
                                " (IEEE 1800-2023 16.12.1)");
        } else if (specp->sensesp()) {
            schemaRefp->v3warn(E_UNSUPPORTED,
                               "Unsupported: clock event in a nested property instance");
        } else if (specp->propp()->exists(
                       [](const AstNodeExpr* np) { return np->isMultiCycleSva(); })
                   && !isInlinableMultiCycle(schemaRefp, specp)) {
            schemaRefp->v3warn(E_UNSUPPORTED,
                               "Unsupported: multi-cycle body in a nested property instance");
        } else {
            // The instance a chain resolves to is checked next, report it at this instance
            if (instancedProperty(specp)) specp->propp()->fileline(schemaRefp->fileline());
            replp = specp->propp()->unlinkFrBack();
        }
        if (!replp) replp = new AstConst{schemaRefp->fileline(), AstConst::BitFalse{}};
        schemaRefp->replaceWith(replp);
        VL_DO_DANGLING(pushDeletep(schemaRefp), schemaRefp);
        VL_DO_DANGLING(pushDeletep(specp), specp);
    }
    // True if a sequence admits an empty match (IEEE 1800-2023 16.12.22), by the derived forms of
    // its operators (IEEE 1800-2023 F.3.4.2). Repetition counts and cycle delays are constants
    // by here.
    static bool admitsEmptyMatch(const AstNodeExpr* nodep) {
        if (const AstSConsRep* const repp = VN_CAST(nodep, SConsRep)) {
            return VN_AS(repp->countp(), Const)->num().isEqZero()
                   || admitsEmptyMatch(repp->exprp());
        }
        if (const AstSExpr* const sexprp = VN_CAST(nodep, SExpr)) {
            // '##[m:n] r' is '1[*m:n] ##1 r'. 'r1 ##[m:n] r2' is 'r1 ##1 1[*m-1:n-1] ##1 r2',
            // or a fusion if m is 0, which matches no empty word, or-ed with the rest of the range
            const AstDelay* const delayp = VN_AS(sexprp->delayp(), Delay);
            const uint32_t minCycles = VN_AS(delayp->lhsp(), Const)->toUInt();
            if (!sexprp->preExprp()) return minCycles == 0 && admitsEmptyMatch(sexprp->exprp());
            const bool rangeHasOne
                = minCycles == 1
                  || (minCycles == 0 && delayp->isRangeDelay()
                      && (delayp->isUnbounded() || VN_AS(delayp->rhsp(), Const)->toUInt() >= 1));
            return rangeHasOne && admitsEmptyMatch(sexprp->preExprp())
                   && admitsEmptyMatch(sexprp->exprp());
        }
        if (const AstSOr* const orp = VN_CAST(nodep, SOr)) {
            return admitsEmptyMatch(orp->lhsp()) || admitsEmptyMatch(orp->rhsp());
        }
        if (const AstSThroughout* const throughoutp = VN_CAST(nodep, SThroughout)) {
            return admitsEmptyMatch(throughoutp->rhsp());
        }
        if (const AstNodeBiop* const biopp = VN_CAST(nodep, NodeBiop)) {
            return (VN_IS(biopp, SAnd) || VN_IS(biopp, SIntersect) || VN_IS(biopp, SWithin))
                   && admitsEmptyMatch(biopp->lhsp()) && admitsEmptyMatch(biopp->rhsp());
        }
        // A boolean; a sequence with match items, a fusion (IEEE 1800-2023 F.3.4.2.4); or a goto
        // or nonconsecutive repetition, whose count V3Width requires to be nonzero
        return false;
    }
    void inlineSequence(AstSchemaRef* schemaRefp, AstSequence* seqp) {
        // Clone the body expression since the sequence may be referenced multiple times
        AstNodeExpr* clonedp = VN_AS(
            V3AssertCommon::relinkSvaInstanceBody(seqp->exprp()->cloneTree(false), schemaRefp),
            NodeExpr);
        coverageOff(clonedp);
        clonedp = VN_AS(substituteArgs(clonedp, schemaRefp, promoteLocalVars(seqp)), NodeExpr);
        schemaRefp->replaceWith(clonedp);
        VL_DO_DANGLING(pushDeletep(schemaRefp), schemaRefp);
        ++m_statSeqInlined;
    }

    // VISITORS
    void visit(AstNodeModule* nodep) override {
        VL_RESTORER(m_modp);
        VL_RESTORER_COPY(m_propVarNames);
        m_modp = nodep;
        m_propVarNames.reset();
        iterateChildren(nodep);
    }
    void visit(AstPropSpec* nodep) override {
        if (AstSchemaRef* const schemaRefp = VN_CAST(nodep->propp(), SchemaRef)) {
            if (AstProperty* const propp = VN_CAST(schemaRefp->schemap(), Property)) {
                // The replacement is iterated next, which inlines a property instance in its body
                inlineProperty(nodep, schemaRefp, propp);
                return;
            }
        }
        iterateAndNextNull(nodep->sensesp());
        {
            VL_RESTORER(m_inDisable);
            m_inDisable = true;
            iterateAndNextNull(nodep->disablep());
        }
        VL_RESTORER(m_inPropExpr);
        m_inPropExpr = true;
        iterateAndNextNull(nodep->propp());
    }
    void visit(AstEventually* nodep) override {
        if (nodep->loBoundp() && !checkSvaEventuallyBounds(nodep)) {
            nodep->replaceWith(new AstConst{nodep->fileline(), AstConst::BitFalseErroring{}});
            VL_DO_DANGLING(pushDeletep(nodep), nodep);
            return;
        }
        iterateChildren(nodep);
    }
    void visit(AstDefaultDisable* nodep) override {
        VL_RESTORER(m_inDisable);
        m_inDisable = true;
        iterateChildren(nodep);
    }
    // A sampled value function in a disable condition has its own clocking event
    // (IEEE 1800-2023 16.9.3)
    void visitSampledValue(AstNodeExpr* nodep, const AstSenTree* sentreep) {
        if (m_inDisable && !sentreep) {
            nodep->v3error("Sampled value function in a disable condition has no clocking event"
                           " (IEEE 1800-2023 16.9.3).\n"
                           << nodep->warnMore()
                           << "... Suggest providing a clocking event argument, or computing the"
                              " value in a clocked procedure");
        }
        iterateChildren(nodep);
    }
    void visit(AstFell* nodep) override { visitSampledValue(nodep, nodep->sentreep()); }
    void visit(AstPast* nodep) override { visitSampledValue(nodep, nodep->sentreep()); }
    void visit(AstRose* nodep) override { visitSampledValue(nodep, nodep->sentreep()); }
    void visit(AstStable* nodep) override { visitSampledValue(nodep, nodep->sentreep()); }
    void visit(AstSenItem* nodep) override {
        // A clocking event inside a property expression has an expression condition
        VL_RESTORER(m_inPropExpr);
        m_inPropExpr = false;
        iterateChildren(nodep);
    }
    void visit(AstSchemaRef* nodep) override {
        AstSequence* const seqp = VN_CAST(nodep->schemap(), Sequence);
        if (!m_inPropExpr) {
            // A sequence or property instance is not an expression (IEEE 1800-2023 16.8, 16.12)
            nodep->v3error("Illegal use of "
                           << (seqp ? "sequence" : "property") << " instance "
                           << nodep->prettyNameQ() << " as an expression"
                           << (seqp ? " (IEEE 1800-2023 16.8)" : " (IEEE 1800-2023 16.12)"));
            return;
        }
        // The replacement is iterated next, which inlines the instances in its body
        if (seqp) {
            inlineSequence(nodep, seqp);
            return;
        }
        // V3LinkResolve substituted every let, so this is a property instance
        inlineNestedProperty(nodep, VN_AS(nodep->schemap(), Property));
    }
    void visit(AstExprStmt* nodep) override {
        // Sequence instances in it are inlined first
        iterateChildren(nodep);
        if (admitsEmptyMatch(nodep->resultp())) {
            nodep->v3error("Match item attached to a sequence that admits an empty match"
                           " (IEEE 1800-2023 16.11).\n"
                           << nodep->warnMore()
                           << "... Suggest attaching it to an enclosing sequence that has no"
                              " empty match.");
        }
    }
    // Declarations are inlined at their instances
    void visit(AstProperty*) override {}
    void visit(AstSequence*) override {}
    // A restrict property is not checked in simulation (IEEE 1800-2023 16.14.4)
    void visit(AstRestrict*) override {}
    void visit(AstNode* nodep) override { iterateChildren(nodep); }

public:
    // CONSTRUCTORS
    explicit AssertElabVisitor(AstNetlist* nodep) { iterate(nodep); }
    ~AssertElabVisitor() override {
        V3Stats::addStat("Assertions, inlined property instances", m_statPropInlined);
        V3Stats::addStat("Assertions, inlined sequence instances", m_statSeqInlined);
    }
};

//######################################################################
// Top AssertElab class

void V3AssertElab::assertElabAll(AstNetlist* nodep) {
    UINFO(2, __FUNCTION__ << ":");
    { SeqEventLowerVisitor{nodep}; }
    { AssertElabVisitor{nodep}; }  // Destruct before checking
    V3Global::dumpCheckGlobalTree("assertelab", 0, dumpTreeEitherLevel() >= 3);
}
